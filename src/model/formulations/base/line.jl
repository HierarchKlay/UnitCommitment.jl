# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

function _add_transmission_line!(
    model::JuMP.Model,
    lm::TransmissionLine,
    f::ShiftFactorsFormulation,
    sc::UnitCommitmentScenario,
)::Nothing
    overflow = _init(model, :overflow)
    for t in 1:model[:instance].time
        overflow[sc.name, lm.name, t] = @variable(model, lower_bound = 0)
        add_to_expression!(
            model[:obj],
            overflow[sc.name, lm.name, t],
            lm.flow_limit_penalty[t] * sc.probability,
        )
    end
    return
end

# overflow is not allowed in all transmission lines 
function _add_restricted_transmission_line!(
    model::JuMP.Model,
    lm::TransmissionLine,
    f::ShiftFactorsFormulation,
    sc::UnitCommitmentScenario,
)::Nothing
    overflow = _init(model, :overflow)
    for t in 1:model[:instance].time
        overflow[sc.name, lm.name, t] = @variable(model, lower_bound = 0, upper_bound = 0)
        add_to_expression!(
            model[:obj],
            overflow[sc.name, lm.name, t],
            lm.flow_limit_penalty[t] * sc.probability,
        )
    end
    return
end

function _setup_transmission(
    formulation::ShiftFactorsFormulation,
    sc::UnitCommitmentScenario,
)::Nothing
    isf = formulation.precomputed_isf
    lodf = formulation.precomputed_lodf
    if length(sc.buses) == 1
        isf = zeros(0, 0)
        lodf = zeros(0, 0)
    elseif isf === nothing
        @info "Computing injection shift factors..."
        time_isf = @elapsed begin
            isf = UnitCommitment._injection_shift_factors(
                buses = sc.buses,
                lines = sc.lines,
            )
        end
        @info @sprintf("Computed ISF in %.2f seconds", time_isf)
        @info "Computing line outage factors..."
        time_lodf = @elapsed begin
            lodf = UnitCommitment._line_outage_factors(
                buses = sc.buses,
                lines = sc.lines,
                isf = isf,
            )
        end
        @info @sprintf("Computed LODF in %.2f seconds", time_lodf)
        @info @sprintf(
            "Applying PTDF and LODF cutoffs (%.5f, %.5f)",
            formulation.isf_cutoff,
            formulation.lodf_cutoff
        )
        isf[abs.(isf).<formulation.isf_cutoff] .= 0
        lodf[abs.(lodf).<formulation.lodf_cutoff] .= 0
    end
    sc.isf = isf
    sc.lodf = lodf
    return
end

# Security constraints using isf and lodf are described in: 

#     Tejada-Arango, D. A., Sánchez-Martın, P., & Ramos, A. (2017). 
#     Security constrained unit commitment using line outage distribution factors. 
#     IEEE Transactions on power systems, 33(1), 329-337.
# 
# 
function _add_pre_contigency_constraints!(
    model::JuMP.Model,
    sc::UnitCommitmentScenario,
)
    overflow = model[:overflow]
    net_injection = model[:net_injection]
    eq_precontig_uplimit = _init(model, :eq_precontig_uplimit)
    eq_precontig_downlimit = _init(model, :eq_precontig_downlimit)
    eq_precontig_flow_def = _init(model, :eq_precontig_flow_def)

    for t in 1:model[:instance].time, lm in sc.lines
        flow = @variable(model, base_name = "flow[$(lm.name),$t]")
        limit = lm.normal_flow_limit[t]
        v = overflow[sc.name, lm.name, t]

        eq_precontig_uplimit[sc.name, lm.name, t] = @constraint(model, flow <= limit + v)
        eq_precontig_downlimit[sc.name, lm.name, t] = @constraint(model, -flow <= limit + v)

        eq_precontig_flow_def[sc.name, lm.name, t] = @constraint(
            model,
            flow == sum(
                net_injection[sc.name, b.name, t] *
                sc.isf[lm.offset, b.offset] for
                b in sc.buses if b.offset > 0
            )
        )
    end

    @info @sprintf("Add %d pre-contingencies security constraints in total", length(sc.lines) * model[:instance].time)
end

function _add_post_contigency_constraints!(
    model::JuMP.Model,
    sc::UnitCommitmentScenario,
)
    overflow = model[:overflow]
    net_injection = model[:net_injection]
    eq_postcontig_uplimit = _init(model, :eq_postcontig_uplimit)
    eq_postcontig_downlimit = _init(model, :eq_postcontig_downlimit)
    eq_postcontig_flow_def = _init(model, :eq_postcontig_flow_def)

    for t in 1:model[:instance].time, lm in sc.lines, contig in sc.contingencies
        length(contig.lines) == 1 || error("The package does NOT support N-k contingency yet.")
        length(contig.thermal_units) == 0 || error("The package does NOT support thermal units contingency yet.")
        
        lc = contig.lines[1]
        flow = @variable(model, base_name = "flow[$(lm.name),$(lc.name),$t]")
        limit = lm.emergency_flow_limit[t]
        v = overflow[sc.name, lm.name, t]

        eq_postcontig_uplimit[sc.name, lm.name, lc.name, t] = @constraint(model, flow <= limit + v)
        eq_postcontig_downlimit[sc.name, lm.name, lc.name, t] = @constraint(model, -flow <= limit + v)

        eq_postcontig_flow_def[sc.name, lm.name, lc.name, t] = @constraint(
            model,
            flow == sum(
                net_injection[sc.name, b.name, t] *(
                    sc.isf[lm.offset, b.offset] + (
                        sc.lodf[
                            lm.offset,
                            lc.offset,
                        ] * sc.isf[lc.offset, b.offset]
                    )
                ) for b in sc.buses if b.offset > 0
            )
        )
    end

    @info @sprintf("Add %d post-contingencies security constraints in total", 
        length(sc.lines) * length(sc.contingencies) * model[:instance].time)
end