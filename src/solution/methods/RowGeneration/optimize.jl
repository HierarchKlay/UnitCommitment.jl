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

    if method.is_gen_min_time
        (haskey(model, :eq_min_uptime) || haskey(model, :eq_min_downtime)) && error("
            Method is based on the formulation without min updown time constraints\n
            Please set is_min_updown=false in build_mymodel()")
    end

    if method.is_gen_pre_conting
        (haskey(model, :eq_preconting_uplimit) || haskey(model, :eq_preconting_downlimit) || 
        haskey(model, :eq_preconting_flow_def)) && error("
            Method is based on the formulation without pre-contingency constraints\n
            Please set is_pre_contingency=false in build_mymodel()")
    end

    if method.is_gen_post_conting
        (haskey(model, :eq_postconting_uplimit) || haskey(model, :eq_postconting_downlimit) || 
        haskey(model, :eq_postconting_flow_def)) && error("
            Method is based on the formulation without post-contingency constraints\n
            Please set is_post_contingency=false in build_mymodel()")
    end
    
    set_gap(method.gap_limit)

    function lazyCons(cb_data)
        isLazy = true
        _callback_function(cb_data, isLazy, model, method)
    end

    
   
    while true
        @info @sprintf("Setting is_gen_min_time=%s",method.is_gen_min_time)
        @info @sprintf("Setting is_gen_pre_conting=%s",method.is_gen_pre_conting)
        @info @sprintf("Setting is_gen_post_conting=%s",method.is_gen_post_conting)
        MOI.set(model, MOI.LazyConstraintCallback(), lazyCons)

        @info "Solving MILP..."
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
        statistic = model[:statistic]
        solt = statistic.time_solve_model
        solt.callback["ver_consec"] = 0.0
        solt.callback["add_consec"] = 0.0
        solt.callback["ver_conting"] = 0.0
        solt.callback["add_conting"] = 0.0
        solt.callback["count_conting"] = 0
        JuMP.set_time_limit_sec(model, time_remaining)
        JuMP.optimize!(model)
        
        break
    end
    return
end
