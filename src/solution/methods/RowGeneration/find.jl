# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

import Base.Threads: @threads

function _find_violations_in_callback(
    cb_data,
    model::JuMP.Model,
    sc::UnitCommitmentScenario;
    max_per_line::Int,
    max_per_period::Int,
    method::RowGeneration.Method,
)
    instance = model[:instance]
    net_injection = model[:net_injection]
    overflow = model[:overflow]
    length(sc.buses) > 1 || return []
    violations = []

    non_slack_buses = [b for b in sc.buses if b.offset > 0]
    net_injection_values = [
        callback_value(cb_data, net_injection[sc.name, b.name, t]) for b in non_slack_buses,
        t in 1:instance.time
    ]
    overflow_values = [
        callback_value(cb_data, overflow[sc.name, lm.name, t]) for lm in sc.lines,
        t in 1:instance.time
    ]
    violations = UnitCommitment._find_violations_in_callback(
        instance = instance,
        sc = sc,
        net_injections = net_injection_values,
        overflow = overflow_values,
        isf = sc.isf,
        lodf = sc.lodf,
        max_per_line = max_per_line,
        max_per_period = max_per_period,
        method = method,
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
function _find_violations_in_callback(;
    instance::UnitCommitmentInstance,
    sc::UnitCommitmentScenario,
    net_injections::Array{Float64,2},
    overflow::Array{Float64,2},
    isf::Array{Float64,2},
    lodf::Array{Float64,2},
    max_per_line::Int,
    max_per_period::Int,
    method::RowGeneration.Method,
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
    if method.is_gen_post_conting
        emergency_limits::Array{Float64,2} = [
            l.emergency_flow_limit[t] + overflow[l.offset, t] for l in sc.lines,
            t in 1:T
        ]
    
        is_vulnerable::Array{Bool} = zeros(Bool, L)
        for c in sc.contingencies
            is_vulnerable[c.lines[1].offset] = true
        end
    end

    @threads for t in 1:T
        k = threadid()

        # Pre-contingency flows
        pre_flow[:, k] = isf * net_injections[:, t]

        # Pre-contingency violations
        for lm in 1:L
            pre_v[lm, k] = max(
                0.0,
                pre_flow[lm, k] - normal_limits[lm, t],
                -pre_flow[lm, k] - normal_limits[lm, t],
            )
        end
        
        if method.is_gen_post_conting
            # Post-contingency flows
            for lc in 1:L, lm in 1:L
                post_flow[lm, lc, k] =
                    pre_flow[lm, k] + pre_flow[lc, k] * lodf[lm, lc]
            end

            # Post-contingency violations
            for lc in 1:L, lm in 1:L
                post_v[lm, lc, k] = max(
                    0.0,
                    post_flow[lm, lc, k] - emergency_limits[lm, t],
                    -post_flow[lm, lc, k] - emergency_limits[lm, t],
                )
            end
        end

        # Offer pre-contingency violations
        for lm in 1:L
            if pre_v[lm, k] > 1e-5
                _offer(
                    filters[t],
                    _Violation(
                        time = t,
                        monitored_line = sc.lines[lm],
                        outage_line = nothing,
                        amount = pre_v[lm, k],
                    ),
                )
            end
        end

        if method.is_gen_post_conting
            # Offer post-contingency violations
            for lm in 1:L, lc in 1:L
                if post_v[lm, lc, k] > 1e-5 && is_vulnerable[lc]
                    _offer(
                        filters[t],
                        _Violation(
                            time = t,
                            monitored_line = sc.lines[lm],
                            outage_line = sc.lines[lc],
                            amount = post_v[lm, lc, k],
                        ),
                    )
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

function _find_consecutiveness_violation_in_callback(
    cb_data,
    model::JuMP.Model,
    sc::UnitCommitmentScenario;
    max_per_unit::Int,
    max_total::Int,
    method::RowGeneration.Method,
)::Array{_Consec_Violation,1}
    is_on = model[:is_on]
    switch_off = model[:switch_off]
    switch_on = model[:switch_on]

    T = sc.time

    # Store the incumbent values 
    is_on_values = Dict((g.name, t) =>
        callback_value(cb_data, is_on[g.name,t]) 
        for g in sc.thermal_units, 
            t in 1:T
    )
    switch_off_values = Dict((g.name, t) =>
        callback_value(cb_data, switch_off[g.name,t]) 
        for g in sc.thermal_units, 
            t in 1:T
    )
    switch_on_values = Dict((g.name, t) =>
        callback_value(cb_data, switch_on[g.name,t]) 
        for g in sc.thermal_units, 
            t in 1:T
    )

    filters = Dict(
        t => _Consec_ViolationFilter(
            max_total = max_total,
            max_per_unit = max_per_unit,
        ) for t in 1:T
    )

    for g in sc.thermal_units, t in 1:T
        if sum(switch_on_values[g.name, i] for i in (t-g.min_uptime+1):t if i >= 1) > is_on_values[g.name, t]
            amount = sum(switch_on_values[g.name, i] for i in (t-g.min_uptime+1):t if i >= 1) - is_on_values[g.name, t]
            _process(
                filters[t],
                _Consec_Violation(
                    time = t,
                    unit = g,
                    is_consec_on = true,
                    is_init_vio = false,
                    amount = amount,
            )
           ) 
        end

        if sum(switch_off_values[g.name, i] for i in (t-g.min_downtime+1):t if i >= 1) > 1 - is_on_values[g.name, t]
            amount = sum(switch_off_values[g.name, i] for i in (t-g.min_downtime+1):t if i >= 1) - 1 + is_on_values[g.name, t]
            _process(
                filters[t],
                _Consec_Violation(
                    time = t,
                    unit = g,
                    is_consec_on = false,
                    is_init_vio = false,
                    amount = amount,
            )
           ) 
        end

        if t == 1
            if g.initial_status > 0 && g.min_uptime-g.initial_status >= 1
                if sum(
                    switch_off_values[g.name, i] for
                    i in 1:(g.min_uptime-g.initial_status) if i <= T
                ) > 0
                    amount = sum(
                        switch_off_values[g.name, i] for
                        i in 1:(g.min_uptime-g.initial_status) if i <= T
                    )
                    _process(
                        filter[t],
                        _Consec_Violation(
                            time = t,
                            unit = g,
                            is_consec_on = true,
                            is_init_vio = true,
                            amount = amount,
                        )
                    )
                end
            elseif g.initial_status <= 0 && g.min_downtime+g.initial_status >= 1
                if sum(
                    switch_on_values[g.name, i] for
                    i in 1:(g.min_downtime+g.initial_status) if i <= T
                ) > 0
                    amount = sum(
                        switch_on_values[g.name, i] for
                        i in 1:(g.min_downtime+g.initial_status) if i <= T
                    )
                    _process(
                        filter[t],
                        _Consec_Violation(
                            time = t,
                            unit = g,
                            is_consec_on = false,
                            is_init_vio = true,
                            amount = amount,
                        )
                    )
                end
            end
        end
                    
    end

    consec_vios = _Consec_Violation[]
    for t in 1:T
        append!(consec_vios, _concat(filters[t]))
    end

    return consec_vios

end