# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

function optimize!(model::JuMP.Model, method::DirectSolve.Method)::Nothing
    
    function set_gap(gap)
        JuMP.set_optimizer_attribute(model, "MIPGap", gap)
        @info @sprintf("MIP gap tolerance set to %f", gap)
    end
    initial_time = time()
    
    set_gap(method.gap_limit)
   
    while true
        time_elapsed = time() - initial_time
        time_remaining = method.time_limit - time_elapsed
        if time_remaining < 0
            @info "Time limit exceeded"
            break
        end
        @info @sprintf(
            "Setting MILP time limit to %.2f seconds",
            time_remaining
        )
        JuMP.set_time_limit_sec(model, time_remaining)
        @info "Solving MILP..."
        JuMP.optimize!(model)

        break
    end
    return
end
