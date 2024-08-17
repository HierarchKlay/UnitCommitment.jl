# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

function optimize!(model::JuMP.Model, method::RowGeneration.Method)::Nothing
    
    function set_gap(gap)
        if occursin("Gurobi", JuMP.solver_name(model))
            JuMP.set_optimizer_attribute(model, "MIPGap", gap)
        elseif occursin("CPLEX", JuMP.solver_name(model))
            JuMP.set_optimizer_attribute(model, "CPXPARAM_MIP_Tolerances_MIPGap", gap)
        end        
        @info @sprintf("MIP gap tolerance set to %f", gap)
    end

    initial_time = time()

    (haskey(model, :eq_min_uptime) || haskey(model, :eq_min_downtime)) && error("
        RowGeneration method is based on the formulation without min updown time constraints\n
        Please set is_min_updown=false in build_mymodel()")
    
    set_gap(method.gap_limit)

    function lazyCons(cb_data)
        isLazy = true
        _callback_function(cb_data, isLazy, model)
    end

    callback_time = 0
   
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
        MOI.set(model, MOI.LazyConstraintCallback(), lazyCons)
        @info "Solving MILP..."
        JuMP.optimize!(model)

        break
    end
    return
end
