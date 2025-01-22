# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

module XQWT2019_mod
import ..SolutionMethod
"""
    mutable struct Method
        time_limit::Float64
        gap_limit::Float64
        two_phase_gap::Bool
        max_violations_per_line::Int
        max_violations_per_period::Int
        max_search_per_period::Int
    end

Surrogate constraint filter method described in:

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
    the desired relative optimality gap. Only used when `two_phase_gap=true`.
- `two_phase_gap`: 
    if true, solve the problem with large gap tolerance first, then reduce
    the gap tolerance when no further violated constraints are found.
- `max_violations_per_line`:
    maximum number of violated transmission constraints to add to the
    formulation per transmission line.
- `max_violations_per_period`:
    maximum number of violated transmission constraints to add to the
    formulation per time period.
- `max_search_per_period`:
    maximum number of transmission constraints searched per time period
    in each iteration.

"""
mutable struct Method <: SolutionMethod
    time_limit::Float64
    gap_limit::Float64
    two_phase_gap::Bool
    max_violations_per_line::Int
    max_violations_per_period::Int
    max_search_per_period::Int

    function Method(;
        time_limit::Float64 = 86400.0,
        gap_limit::Float64 = 1e-3,
        two_phase_gap::Bool = true,
        max_violations_per_line::Int = 1,
        max_violations_per_period::Int = 5,
        max_search_per_period::Int = 5,
    )
        return new(
            time_limit,
            gap_limit,
            two_phase_gap,
            max_violations_per_line,
            max_violations_per_period,
            max_search_per_period,
        )
    end
end
end
