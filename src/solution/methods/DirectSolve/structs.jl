# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

module DirectSolve
import ..SolutionMethod
"""
    mutable struct Method
        time_limit::Float64
        gap_limit::Float64
    end

Fields
------

- `time_limit`:
    the time limit over the entire optimization procedure.
- `gap_limit`: 
    the desired relative optimality gap. 

"""
mutable struct Method <: SolutionMethod
    time_limit::Float64
    gap_limit::Float64

    function Method(;
        time_limit::Float64 = 7200.0,
        gap_limit::Float64 = 1e-3,
        )
        return new(
            time_limit,
            gap_limit,
        )
    end
end
end
