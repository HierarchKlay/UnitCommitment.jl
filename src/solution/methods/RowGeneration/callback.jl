function _callback_function(cb_data, isLazy, model)
    
    Cons = isLazy == true ? MOI.LazyConstraint : MOI.UserCut
    status = callback_node_status(cb_data, model)
    
    # When obtaining an incumbent of the original problems, do the callback
    if status == MOI.CALLBACK_NODE_STATUS_INTEGER
        @info "Do callback now..."

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

end