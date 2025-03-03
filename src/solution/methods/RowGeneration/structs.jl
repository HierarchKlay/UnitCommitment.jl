# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

module RowGeneration
import ..SolutionMethod
"""
    mutable struct Method
        time_limit::Float64
        gap_limit::Float64
        is_root_check::Bool
        is_gen_min_time::Bool
        is_gen_pre_conting::Bool
        is_gen_post_conting::Bool
        is_early_stopped::Bool
        max_violations_per_line::Int
        max_violations_per_period::Int
        max_violations_per_unit::Int
        max_search_per_period::Int
    end

Row generation method described in:

    TANG Yu-Yang, CHEN Liang, CHEN Sheng-Jie. 
    Surrogate Lazy Constraint Filtering Method for 
    the Security-Constrained Unit Commitment Problem[J]. 
    Journal of Xiangtan University (Natural Science Edition), 2024 
    DOI:10.13715/j.issn.2096-644X.20240910.0001.


Fields
------

- `time_limit`:
    the time limit over the entire optimization procedure.
- `gap_limit`: 
    the desired relative optimality gap. 
- `is_root_check`:
    if true, check for violated constraints at the root node.
- `is_gen_min_time`:
    if true, generate minimum time constraints as lazy constraints.
- `is_gen_pre_conting`:
    if true, generate pre-contingency constraints as lazy constraints.
- `is_gen_post_conting`:
    if true, generate post-contingency constraints as lazy constraints.
- `is_early_stopped`:
    if true, stop the checking procedure on violated constraints when number
    of checked constraints exceeds the limit.
- `max_violations_per_line`:
    maximum number of violated transmission constraints to add to the
    formulation per transmission line.
- `max_violations_per_period`:
    maximum number of violated transmission constraints to add to the
    formulation per time period.
- `max_violations_per_unit`:
    maximum number of violated transmission constraints to add to the
    formulation per thermal unit.
- `max_search_per_period`:
    maximum number of transmission constraints searched per time period
    in each iteration.

"""
mutable struct Method <: SolutionMethod
    time_limit::Float64
    gap_limit::Float64
    is_root_check::Bool
    is_gen_min_time::Bool
    is_gen_pre_conting::Bool
    is_gen_post_conting::Bool
    is_early_stopped::Bool
    max_violations_per_line::Int
    max_violations_per_period::Int
    max_violations_per_unit::Int
    max_search_per_period::Int

    function Method(;
        time_limit::Float64 = 3600.0,
        gap_limit::Float64 = 1e-3,
        is_root_check::Bool = false,
        is_gen_min_time::Bool = false,
        is_gen_pre_conting::Bool = true,
        is_gen_post_conting::Bool = true,
        is_early_stopped::Bool = false,
        max_violations_per_line::Int = 1,
        max_violations_per_period::Int = 5,
        max_violations_per_unit::Int = 1,
        max_search_per_period::Int = 5,
    )
        return new(
            time_limit,
            gap_limit,
            is_root_check,
            is_gen_min_time,
            is_gen_pre_conting,
            is_gen_post_conting,
            is_early_stopped,
            max_violations_per_line,
            max_violations_per_period,
            max_violations_per_unit,
            max_search_per_period,
        )
    end
    
end
end

import DataStructures: PriorityQueue

struct _Consec_Violation
    time::Int
    unit::ThermalUnit
    is_consec_on::Bool
    is_init_vio::Bool
    amount::Float64

    function _Consec_Violation(;
        time::Int,
        unit::ThermalUnit,
        is_consec_on::Bool,
        is_init_vio::Bool,
        amount::Float64,
    )
        return new(time, unit, is_consec_on, is_init_vio, amount)
    end
end

mutable struct _Consec_ViolationFilter
    max_per_unit::Int
    max_total::Int
    queues::Dict{AbstractString,PriorityQueue{_Consec_Violation,Float64}}

    function _Consec_ViolationFilter(; max_per_unit::Int = 1, max_total::Int = 5)
        return new(max_per_unit, max_total, Dict())
    end
end

