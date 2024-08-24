# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

function statistic(
    model::JuMP.Model,
    method::DirectSolve.Method,
)::Statistic    
    statistic = model[:statistic]
    statistic.time_solve_model.total = JuMP.solve_time(model)
    statistic.num_node = JuMP.node_count(model)
    return statistic
end

function statistic(
    model::JuMP.Model,
    method::RowGeneration.Method,
)::Statistic    
    statistic = model[:statistic]
    statistic.time_solve_model.total = JuMP.solve_time(model)
    statistic.num_node = JuMP.node_count(model)
    return statistic
end

function statistic(
    model::JuMP.Model,
    method::XavQiuWanThi2019.Method,
)::Statistic    
    statistic = model[:statistic]
    statistic.num_node = statistic.num_node / statistic.time_solve_model.tcf["count_iter"]
    return statistic
end

function statistic(model::JuMP.Model)::Statistic 
    return statistic(model, model[:statistic].method)
end

mutable struct SolveStat
    total::Float64
    callback::OrderedDict{AbstractString, Union{Float64, Int}}
    tcf::OrderedDict{AbstractString, Union{Float64, Int}}
end

mutable struct Statistic
    method::Union{SolutionMethod, Nothing}
    time_build_model::OrderedDict{AbstractString, Float64}
    time_solve_model::SolveStat
    num_node::Union{Int, Float64}
    
    Statistic() = new(
        nothing,
        OrderedDict{AbstractString, Float64}(),
        SolveStat(
            0.0, 
            OrderedDict{AbstractString, Union{Float64, Int}}(), 
            OrderedDict{AbstractString, Union{Float64, Int}}(),
        ),
        0,
    )

end