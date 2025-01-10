# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

import Base.Threads: @threads

function _find_surrogate_violations(
    model::JuMP.Model,
    sc::UnitCommitmentScenario;
    max_per_line::Int,
    max_per_period::Int,
)
    instance = model[:instance]
    net_injection = model[:net_injection]
    overflow = model[:overflow]
    length(sc.buses) > 1 || return []
    violations = []

    non_slack_buses = [b for b in sc.buses if b.offset > 0]
    net_injection_values = [
        value(net_injection[sc.name, b.name, t]) for b in non_slack_buses,
        t in 1:instance.time
    ]
    overflow_values = [
        value(overflow[sc.name, lm.name, t]) for lm in sc.lines,
        t in 1:instance.time
    ]
    violations = UnitCommitment._find_surrogate_violations(
        instance = instance,
        sc = sc,
        net_injections = net_injection_values,
        overflow = overflow_values,
        isf = sc.isf,
        lodf = sc.lodf,
        max_per_line = max_per_line,
        max_per_period = max_per_period,
    )
    return violations
end

"""
    function _find_violations(
        instance::UnitCommitmentInstance,
        net_injections::Array{Float64, 2};
        isf::Array{Float64,2},
        lodf::Array{Float64,2},
        max_per_line::Int,
        max_per_period::Int,
    )::Array{_Violation, 1}

Find transmission constraint violations (both pre-contingency, as well as
post-contingency).

The argument `net_injection` should be a (B-1) x T matrix, where B is the
number of buses and T is the number of time periods. The arguments `isf` and
`lodf` can be computed using UnitCommitment.injection_shift_factors and
UnitCommitment.line_outage_factors. The argument `overflow` specifies how much
flow above the transmission limits (in MW) is allowed. It should be an L x T
matrix, where L is the number of transmission lines.
"""
function _find_surrogate_violations(;
    instance::UnitCommitmentInstance,
    sc::UnitCommitmentScenario,
    net_injections::Array{Float64,2},
    overflow::Array{Float64,2},
    isf::Array{Float64,2},
    lodf::Array{Float64,2},
    max_per_line::Int,
    max_per_period::Int,
)::Array{_Violation,1}
    B = length(sc.buses) - 1
    L = length(sc.lines)
    T = instance.time
    K = nthreads()

    size(net_injections) == (B, T) || error("net_injections has incorrect size")
    size(isf) == (L, B) || error("isf has incorrect size")
    size(lodf) == (L, L) || error("lodf has incorrect size")

    filters = Dict(
        t => _ViolationFilter(
            max_total = max_per_period,
            max_per_line = max_per_line,
        ) for t in 1:T
    )

    pre_flow::Array{Float64} = zeros(L, K)           # pre_flow[lm, thread]
    post_flow::Array{Float64} = zeros(L, L, K)       # post_flow[lm, lc, thread]
    pre_v::Array{Float64} = zeros(L, K)              # pre_v[lm, thread]
    post_v::Array{Float64} = zeros(L, L, K)          # post_v[lm, lc, thread]

    normal_limits::Array{Float64,2} = [
        l.normal_flow_limit[t] + overflow[l.offset, t] for l in sc.lines,
        t in 1:T
    ]

    emergency_limits::Array{Float64,2} = [
        l.emergency_flow_limit[t] + overflow[l.offset, t] for l in sc.lines,
        t in 1:T
    ]

    is_vulnerable::Array{Bool} = zeros(Bool, L)
    for c in sc.contingencies
        is_vulnerable[c.lines[1].offset] = true
    end

    count_pre_vio = [Threads.Atomic{Int}(0) for _ in 1:T]
    pre_stop_flags = [Threads.Atomic{Bool}(false) for _ in 1:T]
    count_post_vio = [Threads.Atomic{Int}(0) for _ in 1:T]
    post_stop_flags = [Threads.Atomic{Bool}(false) for _ in 1:T]

    # target_count = 5

    @threads for t in 1:T
        k = threadid()

        # Pre-contingency flows
        pre_flow[:, k] = isf * net_injections[:, t]

        # Pre-contingency violations
        for lm in 1:L
            if pre_stop_flags[t][]
                break
            end

            pre_v[lm, k] = max(
                0.0,
                pre_flow[lm, k] - normal_limits[lm, t],
                -pre_flow[lm, k] - normal_limits[lm, t],
            )
            if pre_v[lm, k] > 1e-5
                current_count = Threads.atomic_add!(count_pre_vio[t], 1)

                _offer(
                    filters[t],
                    _Violation(
                        time = t,
                        monitored_line = sc.lines[lm],
                        outage_line = nothing,
                        amount = pre_v[lm, k],
                    ),
                )

                if current_count >= target_count
                    Threads.atomic_cas!(pre_stop_flags[t], false, true)
                    break
                end
            end
        end

        # Post-contingency violations
        outer_break = false  
        for lc in 1:L
            if is_vulnerable[lc]
                if post_stop_flags[t][]
                    break
                end

                for lm in 1:L
                    if post_stop_flags[t][]
                        outer_break = true
                        break
                    end

                    post_flow[lm, lc, k] =
                        pre_flow[lm, k] + pre_flow[lc, k] * lodf[lm, lc]
                    
                    post_v[lm, lc, k] = max(
                        0.0,
                        post_flow[lm, lc, k] - emergency_limits[lm, t],
                        -post_flow[lm, lc, k] - emergency_limits[lm, t],
                    )

                    if post_v[lm, lc, k] > 1e-5
                        current_count = Threads.atomic_add!(count_post_vio[t], 1)

                        _offer(
                            filters[t],
                            _Violation(
                                time = t,
                                monitored_line = sc.lines[lm],
                                outage_line = sc.lines[lc],
                                amount = post_v[lm, lc, k],
                            ),
                        )

                        if current_count >= target_count
                            Threads.atomic_cas!(post_stop_flags[t], false, true)
                            outer_break = true
                            break
                        end
                    end
                end

                if outer_break
                    break
                end 
            end
        end
    end

    violations = _Violation[]
    for t in 1:instance.time
        append!(violations, _query(filters[t]))
    end

    return violations
end
