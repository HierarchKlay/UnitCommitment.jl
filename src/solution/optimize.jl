# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

"""
    optimize!(model::JuMP.Model)::Nothing

Solve the given unit commitment model. Unlike `JuMP.optimize!`, this uses more
advanced methods to accelerate the solution process and to enforce transmission
and N-1 security constraints.
"""
function optimize!(model::JuMP.Model)::Nothing
    return UnitCommitment.optimize!(model, XavQiuWanThi2019.Method())
end

# solve the security constrained unit commitment problem directly
function direct_optimize!(model::JuMP.Model)::Nothing
    return UnitCommitment.optimize!(model, DirectSolve.Method())
end

# solve the security constrained unit commitment problem with callback on min updown time constraints
function callback_optimize!(;
    model::JuMP.Model,
    is_gen_min_time::Bool = true,
    is_gen_pre_conting::Bool = true,
    is_gen_post_conting::Bool = true,
)::Nothing
    return UnitCommitment.optimize!(model, RowGeneration.Method(
        is_gen_min_time=is_gen_min_time,
        is_gen_pre_conting=is_gen_pre_conting,
        is_gen_post_conting=is_gen_post_conting,
    ))
end