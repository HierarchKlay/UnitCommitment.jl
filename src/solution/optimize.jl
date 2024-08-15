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

# solve the unit commitment problem without considering transmission-related constraints
function optimizeUC!(model::JuMP.Model)::Nothing
    return UnitCommitment.optimize!(model, UCSolve.Method())
end