# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

module ColumnGeneration
import ..SolutionMethod

"""
    MasterParams
    A structure to define parameters specific to the master problem.

    Fields
    ------

    - `time_limit`: Time limit for solving the master problem.
    - `gap_limit`: Desired relative optimality gap for the master problem.
    - `solver`: Solver for the master problem.
"""
mutable struct MasterParams
    time_limit::Float64
    gap_limit::Float64
    solver::Any

    function MasterParams(;
        time_limit::Float64 = 3600.0,
        gap_limit::Float64 = 1e-3,
        solver = nothing,
    )
        return new(
            time_limit, 
            gap_limit, 
            solver
        )
    end
end

"""
    SubParams
    A structure to define parameters specific to the subproblem.

    Fields
    ------

    - `time_limit`: Time limit for solving the subproblem.
    - `gap_limit`: Desired relative optimality gap for the subproblem.
    - `solver`: Solver for the subproblem.
"""
mutable struct SubParams
    time_limit::Float64
    gap_limit::Float64
    solver::Any

    function SubParams(;
        time_limit::Float64 = 3600.0,
        gap_limit::Float64 = 1e-3,
        solver = nothing
    )
        return new(
            time_limit, 
            gap_limit, 
            solver
        )
    end
end


"""
    mutable struct Method
    A structure to define the overall configuration for the column generation method.

    Fields
    ------

    - `master_params`: Parameters for the master problem.
    - `sub_params`: Parameters for the subproblem.
"""
mutable struct Method <: SolutionMethod
    master_params::MasterParams
    sub_params::SubParams
    statistic::Any

    function Method(;
        master_params::MasterParams = MasterParams(),
        sub_params::SubParams = SubParams(),
        statistic::Any = nothing
    )
        return new(
            master_params, 
            sub_params,
            statistic,
        )
    end
end
end

struct _Schedule
    name::String  # name of the schedule
    unit::ThermalUnit  # unit is the thermal unit of the schedule
    w::Vector{Int}  # w[t] is the state value at time t
    is_on::Vector{Int}  # is_on[t] is state value at time t derived from w, typically is_on = w
    switch_on::Vector{Int}  # switch_on[t] is switch-on indicator value at time t derived from w
    switch_off::Vector{Int}  # switch_off[t] is switch-off indicator value at time t derived from w
end



