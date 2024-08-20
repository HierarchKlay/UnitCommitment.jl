function _callback_function(cb_data, isLazy, model, method)
    
    Cons = isLazy == true ? MOI.LazyConstraint : MOI.UserCut
    status = callback_node_status(cb_data, model)
    
    # When obtaining an incumbent of the original problems, do the callback
    if status == MOI.CALLBACK_NODE_STATUS_INTEGER
        @info "Do callback now..."
        
        if method.is_gen_min_time
            start_time = time()
            _generate_min_updown_time_constraints(cb_data, model, Cons)
            @info @sprintf("Added min_updown_time constraints in %.2f seconds", time()-start_time)
        end

        has_transmission = length(model[:instance].scenarios[1].isf) > 0

        if !has_transmission
            return
        end

        if method.is_gen_post_conting || method.is_gen_post_conting
            @info "Verifying transmission limits..."
            verify_start_time = time()
            violations = []
            for sc in model[:instance].scenarios
                push!(
                    violations,
                    _find_violations_in_callback(
                        cb_data,
                        model,
                        sc,
                        max_per_line = method.max_violations_per_line,
                        max_per_period = method.max_violations_per_period,
                        method = method
                    ),
                )

            end
            time_screening = time() - verify_start_time
            @info @sprintf(
            "Verified transmission limits in %.2f seconds",
            time_screening
            )

            violations_found = false
            for v in violations
                if !isempty(v)
                    violations_found = true
                end
            end

            if violations_found
                for (i, v) in enumerate(violations)
                    _generate_contingency_constraints(cb_data, model, Cons, v, model[:instance].scenarios[i], method)
                end
            else
                @info "No violations found"
            end
            
        end
        
        
    end
end

function _generate_min_updown_time_constraints(cb_data, model, Cons)
    is_on = model[:is_on]
    switch_off = model[:switch_off]
    switch_on = model[:switch_on]

    T = model[:instance].time
    
    # Store the incumbent values 
    is_on_values = Dict((g.name, t) =>
        callback_value(cb_data, is_on[g.name,t]) 
        for g in model[:instance].scenarios[1].thermal_units, 
            t in 1:T
    )
    switch_off_values = Dict((g.name, t) =>
        callback_value(cb_data, switch_off[g.name,t]) 
        for g in model[:instance].scenarios[1].thermal_units, 
            t in 1:T
    )
    switch_on_values = Dict((g.name, t) =>
        callback_value(cb_data, switch_on[g.name,t]) 
        for g in model[:instance].scenarios[1].thermal_units, 
            t in 1:T
    )

    eq_min_uptime = _init(model, :eq_min_uptime)
    eq_min_downtime = _init(model, :eq_min_downtime)

    for g in model[:instance].scenarios[1].thermal_units, t in 1:T
        if sum(switch_on_values[g.name, i] for i in (t-g.min_uptime+1):t if i >= 1) > is_on_values[g.name, t]
            # Minimum up-time
            @info "Constraints eq_min_uptime[$(g.name), $t] violated"
            eq_min_uptime[g.name, t] = @build_constraint(
                sum(
                    switch_on[g.name, i] for i in (t-g.min_uptime+1):t if i >= 1
                ) <= is_on[g.name, t]
            )
            MOI.submit(model, Cons(cb_data), eq_min_uptime[g.name, t])
        end
        if sum(switch_off_values[g.name, i] for i in (t-g.min_downtime+1):t if i >= 1) > 1 - is_on_values[g.name, t]
            @info "Constraints eq_min_downtime[$(g.name), $t] violated"
            # Minimum down-time
            eq_min_downtime[g.name, t] = @build_constraint(
                sum(
                    switch_off[g.name, i] for i in (t-g.min_downtime+1):t if i >= 1
                ) <= 1 - is_on[g.name, t]
            )
            MOI.submit(model, Cons(cb_data), eq_min_downtime[g.name, t])
        end
        # Minimum up/down-time for initial periods
        if t == 1
            if g.initial_status > 0 && g.min_uptime-g.initial_status >= 1
                if sum(
                    switch_off_values[g.name, i] for
                    i in 1:(g.min_uptime-g.initial_status) if i <= T
                ) > 0
                    @info "Constraints eq_min_uptime[$(g.name), 0] violated"
                    eq_min_uptime[g.name, 0] = @build_constraint(
                        sum(
                            switch_off[g.name, i] for
                            i in 1:(g.min_uptime-g.initial_status) if i <= T
                        ) == 0
                    )
                    MOI.submit(model, Cons(cb_data), eq_min_uptime[g.name, 0])
                end
            elseif g.initial_status <= 0 && g.min_downtime+g.initial_status >= 1
                if sum(
                    switch_on_values[g.name, i] for
                    i in 1:(g.min_downtime+g.initial_status) if i <= T
                ) > 0
                    @info "Constraints eq_min_downtime[$(g.name), 0] violated"
                    eq_min_downtime[g.name, 0] = @build_constraint(
                        sum(
                            switch_on[g.name, i] for
                            i in 1:(g.min_downtime+g.initial_status) if i <= T
                        ) == 0
                    )
                    MOI.submit(model, Cons(cb_data), eq_min_downtime[g.name, 0])
                end
            end
        end
    end

end

function _generate_contingency_constraints(cb_data, model, Cons, violations, sc, method)
    for violation in violations
        limit::Float64 = 0.0
        overflow = model[:overflow]
        net_injection = model[:net_injection]

        if violation.outage_line === nothing
            limit = violation.monitored_line.normal_flow_limit[violation.time]
            @info @sprintf(
                "    %8.3f MW overflow in %-5s time %3d (pre-contingency, scenario %s)",
                violation.amount,
                violation.monitored_line.name,
                violation.time,
                sc.name,
            )
        else
            method.is_gen_post_conting == true || error("DEBUG: The outage violation should NOT appear here!")
            limit = violation.monitored_line.emergency_flow_limit[violation.time]
            @info @sprintf(
                "    %8.3f MW overflow in %-5s time %3d (outage: line %s, scenario %s)",
                violation.amount,
                violation.monitored_line.name,
                violation.time,
                violation.outage_line.name,
                sc.name,
            )
        end

        lm = violation.monitored_line
        fm = violation.monitored_line.name
        t = violation.time
        v = overflow[sc.name, violation.monitored_line.name, violation.time]
        
        if violation.outage_line === nothing
            eq_preconting_uplimit = _init(model, :eq_preconting_uplimit)
            eq_preconting_downlimit = _init(model, :eq_preconting_downlimit)
            
            if !haskey(eq_preconting_uplimit, (sc.name, fm, t))
                eq_preconting_uplimit[sc.name, fm, t] = @build_constraint(
                    sum(
                        net_injection[sc.name, b.name, t] *
                        sc.isf[lm.offset, b.offset] for
                        b in sc.buses if b.offset > 0
                    ) <= limit + v)
                eq_preconting_downlimit[sc.name, fm, t] = @build_constraint(
                    -sum(
                        net_injection[sc.name, b.name, t] *
                        sc.isf[lm.offset, b.offset] for
                        b in sc.buses if b.offset > 0
                    ) <= limit + v)
                MOI.submit(model, Cons(cb_data), eq_preconting_uplimit[sc.name, fm, t])
                MOI.submit(model, Cons(cb_data), eq_preconting_downlimit[sc.name, fm, t])
            else
                error("Pre-contingecy constraints are already added.
                     But they are still violated by the incumbent.")
            end
        else 
            lc = violation.outage_line
            fc = violation.outage_line.name
            eq_postconting_uplimit = _init(model, :eq_postconting_uplimit)
            eq_postconting_downlimit = _init(model, :eq_postconting_downlimit)
            
            if !haskey(eq_postconting_uplimit, (sc.name, fm, fc, t))
                eq_postconting_uplimit[sc.name, fm, fc, t] = @build_constraint(
                    sum(
                        net_injection[sc.name, b.name, t] *(
                            sc.isf[lm.offset, b.offset] + (
                                sc.lodf[
                                    lm.offset,
                                    lc.offset,
                                ] * sc.isf[lc.offset, b.offset]
                            )
                        ) for b in sc.buses if b.offset > 0
                    ) <= limit + v)
                eq_postconting_downlimit[sc.name, fm, fc, t] = @build_constraint(
                    -sum(
                        net_injection[sc.name, b.name, t] *(
                            sc.isf[lm.offset, b.offset] + (
                                sc.lodf[
                                    lm.offset,
                                    lc.offset,
                                ] * sc.isf[lc.offset, b.offset]
                            )
                        ) for b in sc.buses if b.offset > 0
                    ) <= limit + v)
                MOI.submit(model, Cons(cb_data), eq_postconting_uplimit[sc.name, fm, fc, t])
                MOI.submit(model, Cons(cb_data), eq_postconting_downlimit[sc.name, fm, fc, t])
            else
                error("Post-contingecy constraints are already added.
                     But they are still violated by the incumbent.")
            end

        end



    end
end
