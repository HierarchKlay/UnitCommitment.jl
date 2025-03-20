# using CPLEX

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

    # Trial: Testing `rootLP_check`
    function rootLP_check(model, method)
        has_transmission = length(model[:instance].scenarios[1].isf) > 0
        if !has_transmission
            return
        end

        if method.is_gen_post_conting || method.is_gen_post_conting
            
            model_copy = build_mymodel(instance=model[:instance],formulation=Formulation(),
                optimizer=CPLEX.Optimizer,is_pre_contingency=false, is_post_contingency=false)
            JuMP.relax_integrality(model_copy)
            JuMP.optimize!(model_copy)

            statistic = model[:statistic]
            statistic.time_solve_model["total"] = 0.0
            # statistic.time_solve_model["total"] += JuMP.solve_time(model_copy)

            @info "Verifying transmission limits..."
            verify_start_time = time()
            violations = []
            for sc in model_copy[:instance].scenarios
                push!(
                    violations,
                    _find_violations_at_root(
                        model_copy,
                        sc,
                        max_per_line = method.max_violations_per_line,
                        max_per_period = method.max_violations_per_period,
                        method = method,
                    ),
                )

            end
            time_screening = time() - verify_start_time
            @info @sprintf(
            "Verified transmission limits in %.2f seconds",
            time_screening
            )
            solt.callback["ver_conting"] += time_screening

            violations_found = false
            for v in violations
                if !isempty(v)
                    violations_found = true
                end
            end

            if violations_found
                solt.callback["count_conting"] += sum(length, violations)
                start_time = time()
                for (i, v) in enumerate(violations)
                    _generate_contingency_constraints(model, v, model[:instance].scenarios[i], method)
                end
                time_gen = time() - start_time
                solt.callback["add_conting"] += time_gen
            else
                @info "No violations found"
            end
        end
    end  # End of rootLP_check function
   
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
        callback = statistic.others.callback
        solt["t_ver_consec"] = 0.0
        solt["t_add_consec"] = 0.0
        solt["t_ver_conting"] = 0.0
        solt["t_add_conting"] = 0.0
        callback["count_conting"] = 0
        callback["count_iter"] = 0
        callback["list_count_conting"] = Int[]
        callback["ts_ver_conting"] = Float64[]

        # Trial: Testing flow definition before callback execution.
        global is_flow_defined = false
        if is_flow_defined     
            time_extra = time()
            sc = model[:instance].scenarios[1]
            net_injection = model[:net_injection]

            flow = _init(model, :flow)
            eq_preconting_flow_def = _init(model, :eq_preconting_flow_def)
            eq_postconting_flow_def = _init(model, :eq_postconting_flow_def)

            for t in 1:model[:instance].time, lm in sc.lines
                limit = lm.normal_flow_limit[t]
                flow[sc.name, lm.name, t] = @variable(model)
            
                eq_preconting_flow_def[sc.name, lm.name, t] = @constraint(
                    model,
                    flow[sc.name, lm.name, t] == sum(
                        net_injection[sc.name, b.name, t] *
                        sc.isf[lm.offset, b.offset] for
                        b in sc.buses if b.offset > 0
                    )
                )
            end

            for t in 1:model[:instance].time, lm in sc.lines, cont in sc.contingencies
                lc = cont.lines[1]
                limit = lm.emergency_flow_limit[t]
                flow[sc.name, lm.name, lc.name, t] = @variable(model)

                eq_postconting_flow_def[sc.name, lm.name, lc.name, t] = @constraint(
                    model,
                    flow[sc.name, lm.name, lc.name, t] == sum(
                        net_injection[sc.name, b.name, t] *(
                            sc.isf[lm.offset, b.offset] + (
                                sc.lodf[
                                    lm.offset,
                                    lc.offset,
                                ] * sc.isf[lc.offset, b.offset]
                            )
                        ) for b in sc.buses if b.offset > 0
                    )
                )

            end
            time_extra = time() - time_extra
            @info "Time to add flow-defining constraints: $(time_extra) seconds"
        end

        JuMP.set_time_limit_sec(model, time_remaining)
        if method.is_root_check
            rootLP_check(model, method)
        end
        JuMP.optimize!(model)
        
        break
    end  
end  