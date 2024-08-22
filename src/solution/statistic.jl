# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

function statistic(model::JuMP.Model;
    method::RowGeneration.Method = RowGeneration.Method()
)::Statistic    
    statistic = model[:statistic]
    statistic.time_solve_model.total = JuMP.solve_time(model)
    return statistic
end

mutable struct SolveTime
    total::Float64
    callback::OrderedDict{AbstractString, Float64}
end

mutable struct Statistic
    time_build_model::OrderedDict{AbstractString, Float64}
    time_solve_model::SolveTime
    
    Statistic() = new(
        OrderedDict{AbstractString, Float64}(),
        SolveTime(0.0, OrderedDict{AbstractString, Float64}()),
    )

end