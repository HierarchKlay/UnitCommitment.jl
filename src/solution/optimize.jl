# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

"""
    optimize!(model::JuMP.Model)::Nothing

Solve the given unit commitment model. Unlike `JuMP.optimize!`, this uses more
advanced methods to accelerate the solution process and to enforce transmission
and N-1 security constraints.
"""
function optimize!(model::JuMP.Model;
    is_early_stopped::Bool = false,
    max_search_per_period::Int = 5,
    max_violations_per_line::Int = 1,
    max_violations_per_period::Int = 5,
)::Nothing
    if is_early_stopped
        model[:statistic].method = XQWT2019_mod.Method(
            max_search_per_period = max_search_per_period,
            max_violations_per_line = max_violations_per_line,
            max_violations_per_period = max_violations_per_period,
        )
    else
        model[:statistic].method = XavQiuWanThi2019.Method(
            max_violations_per_line = max_violations_per_line,
            max_violations_per_period = max_violations_per_period,
        )
    end
    return UnitCommitment.optimize!(model, model[:statistic].method)
end

# solve the security constrained unit commitment problem directly
function direct_optimize!(model::JuMP.Model; time_limit=7200.0, gap=1e-3)::Nothing
    method = DirectSolve.Method(time_limit=time_limit, gap_limit=gap)
    model[:statistic].method = method
    return UnitCommitment.optimize!(model, method)
end

# solve the security constrained unit commitment problem with SLCF method
function callback_optimize!(;
    model::JuMP.Model,
    is_root_check::Bool = false,
    is_gen_min_time::Bool = false,
    is_gen_pre_conting::Bool = true,
    is_gen_post_conting::Bool = true,
    is_early_stopped::Bool = false,
    max_search_per_period::Int = 5,
    max_violations_per_period::Int = 5,
)::Nothing
    model[:statistic].method = RowGeneration.Method(
        is_root_check=is_root_check,
        is_gen_min_time=is_gen_min_time,
        is_gen_pre_conting=is_gen_pre_conting,
        is_gen_post_conting=is_gen_post_conting,
        is_early_stopped=is_early_stopped,
        max_search_per_period=max_search_per_period,
        max_violations_per_period = max_violations_per_period
    )
    return UnitCommitment.optimize!(model, model[:statistic].method)
end

function CG_optimize!(;
    instance::UnitCommitmentInstance,
    mas_optimizer = nothing,
    mas_time_limit = 7200.0,
    mas_gap = 1e-3, 
    sub_optimizer = nothing,  
    sub_time_limit = 7200.0,
    sub_gap = 1e-3,
)
    method = ColumnGeneration.Method(
        master_params=ColumnGeneration.MasterParams(
            time_limit=mas_time_limit,
            gap_limit=mas_gap,
            solver=mas_optimizer
            ),
        sub_params=ColumnGeneration.SubParams(
            time_limit=sub_time_limit,
            gap_limit=sub_gap,
            solver=sub_optimizer,
            )
    )
    return UnitCommitment.optimize!(instance, method)
end