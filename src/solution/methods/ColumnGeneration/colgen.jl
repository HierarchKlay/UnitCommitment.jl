# Components of Column Generation

# Column generation algorithm
function _column_generation(
    instance::UnitCommitmentInstance,
    initial_schedules::Vector{_Schedule},
    master_optimizer,
    sub_optimizer,
    is_aggr_θ::Bool,
    stat,
)
    if !is_aggr_θ
        # Initialize the RMP
        tbm = stat.time_build_model
        tbm["t_build_rmp"] += @elapsed begin
            rmp, θ, coeffs = _initialize_rmp(instance, initial_schedules, master_optimizer)
        end
        @info "RMP initialized"
        tbm["t_build_sp"] = 0.0
        tbm["t_build_sp"] += @elapsed begin
            subproblems = _initialize_subproblems(instance, sub_optimizer)
        end 
        @info "Subproblems initialized"
        iteration = 0
        tsm = stat.time_solve_model
        tsm["t_solve_rmp"] = 0.0
        tsm["t_solve_sp"] = 0.0
        cg = stat.others.cg
        cg["ts_solve_rmp"] = Float64[]
        cg["ts_solve_sp"] = Float64[]
        cg["reduced_costs"] = Float64[]
        cg["list_count_schedules"] = Int[]
        
        while true 
            iteration += 1
            # if iteration > 10
            #     break
            # end
            if iteration > 1
                # update timelimit for the RMP
                if time_limit_sec(rmp) - cg["ts_solve_rmp"][end] >= 1
                    set_time_limit_sec(rmp, time_limit_sec(rmp) - cg["ts_solve_rmp"][end])
                else
                    cg["count_CG_iters"] = iteration
                    cg["count_schedules"] = length(initial_schedules)
                    @info "Terminate the column generation algorithm due to time limit of RMP"
                    break
                end
            end
            # Solve the RMP
            time_rmp = @elapsed begin
                JuMP.optimize!(rmp)
            end
            tsm["t_solve_rmp"] += time_rmp
            push!(cg["ts_solve_rmp"], time_rmp)

            print_step = 5
            if iteration % print_step == 1
                @info "Iteration $(iteration)"
                current_objective = objective_value(rmp)
                println("Current objective: ", current_objective)
            end
            # @info "Iteration $(iteration)"
            # current_objective = objective_value(rmp)
            # println("Current objective: ", current_objective)
            if termination_status(rmp) != MOI.OPTIMAL
                @warn "RMP in iteration $(iteration) is not solved to optimal!"
                println("termination_status = $(termination_status(rmp))")
            end
            
            # if termination_status(rmp) == MOI.INFEASIBLE
            #     println("RMP is not infeasible")
            #     compute_conflict!(rmp)
            #     println("Conflict detected")
            #     iis_model, _ = copy_conflict(rmp)
            #     println(iis_model)
            # end
            
            # Obtain the dual values
            # println("initial_schedules: ", initial_schedules)
            
            dual_values = _get_dual_values(instance, rmp)
            # for schedule in initial_schedules
            #     println("Before:initial_schedules: ", schedule.name)
            # end
            if iteration > 1
                # update timelimit for the subproblems
                for sp in values(subproblems)
                    if time_limit_sec(sp) - cg["ts_solve_sp"][end] >= 1
                        set_time_limit_sec(sp, time_limit_sec(sp) - cg["ts_solve_sp"][end])
                    else
                        cg["count_CG_iters"] = iteration
                        cg["count_schedules"] = length(initial_schedules)
                        @info "Terminate the column generation algorithm due to time limit of subproblems"
                        break
                    end
                end
            end

            time_sp = @elapsed begin
                new_schedules, reduced_costs = _solve_subproblems(instance, dual_values, subproblems, initial_schedules)
            end
            tsm["t_solve_sp"] += time_sp
            push!(cg["ts_solve_sp"], time_sp)
            # if iteration % print_step == 1
            #     min_redcost = minimum(values(reduced_costs))
            #     println("Minimum reduced cost: ", min_redcost)
            # end
            min_redcost = minimum(values(reduced_costs))
            println("Minimum reduced cost: ", min_redcost)
            push!(cg["reduced_costs"], min_redcost)
           
            if all(reduced_cost -> reduced_cost >= -1e-6, values(reduced_costs))
                cg["count_CG_iters"] = iteration
                cg["count_schedules"] = length(initial_schedules)
                @info "Terminate the column generation algorithm"
                break
            end

            # for schedule in initial_schedules
            #     if abs(value(θ[schedule.name])) >= 1e-6
            #         println("θ[$(schedule.name)] = ", value(θ[schedule.name]))
            #     end
            # end

            # Update RMP with new columns
            num_new_schedules = 0
            tbm["t_build_rmp"] += @elapsed begin
                for schedule in new_schedules
                    if schedule !== nothing && reduced_costs[schedule.unit.name] < -1e-6
                        # println("add new column: ", schedule.name)
                        push!(initial_schedules, schedule)
                        num_new_schedules += 1
                        θ[schedule.name] = @variable(rmp, lower_bound = 0, base_name="theta[$(schedule.name)]")
                        C, U, SU, SD, N = _compute_coefficients(instance, schedule)
                        coeffs[schedule.name] = Dict(:C => C, :U => U, :SU => SU, :SD => SD, :N => N)

                        # Update the objective function
                        set_objective_coefficient(rmp, θ[schedule.name], C)

                        # Update the constraints with θ
                        eq_prod_limit = rmp[:eq_prod_limit]
                        eq_startup_limit = rmp[:eq_startup_limit]
                        eq_shutdown_limit = rmp[:eq_shutdown_limit]
                        eq_power_balance = rmp[:eq_power_balance]
                        eq_convexity = rmp[:eq_convexity]

                        if schedule.unit.initial_power > schedule.unit.shutdown_limit
                            set_normalized_coefficient(eq_shutdown_limit[schedule.unit.name, 0], θ[schedule.name], -schedule.switch_off[1])
                        end

                        for t in 1:instance.time
                            set_normalized_coefficient(eq_prod_limit[schedule.unit.name, t], θ[schedule.name], U[t])
                            set_normalized_coefficient(eq_startup_limit[schedule.unit.name, t], θ[schedule.name], SU[t])
                            if t < instance.time
                                set_normalized_coefficient(eq_shutdown_limit[schedule.unit.name, t], θ[schedule.name], SD[t+1])
                            end
                            set_normalized_coefficient(eq_power_balance[t], θ[schedule.name], N[t])
                            set_normalized_coefficient(eq_convexity[schedule.unit.name], θ[schedule.name], -1)
                        end
                    end
                end
            end
            push!(cg["list_count_schedules"], num_new_schedules)
           
            # for schedule in initial_schedules
            #     println("After:initial_schedules: ", schedule.name)
            # end
        end
        

    else
        
    end

    return rmp, initial_schedules, θ, stat
end

# Initialize the RMP
function _initialize_rmp(
    instance::UnitCommitmentInstance,
    initial_schedules::Vector{_Schedule},
    optimizer,
)
    model = Model(optimizer)

    sc = instance.scenarios[1]
    T = instance.time

    # Define continuous variables
    prod_above = _init(model, :prod_above)
    segprod = _init(model, :segprod)
    reserve = _init(model, :reserve)
    for g in sc.thermal_units
        for t in 1:T
            for k in 1:length(g.cost_segments)
                segprod[g.name, t, k] = @variable(model, lower_bound = 0, base_name="segprod[$(g.name),$t,$k]")
            end
            prod_above[g.name, t] = @variable(model, lower_bound = 0, base_name="prod_above[$(g.name),$t]")
        end
        for r in g.reserves
            r.type == "spinning" || continue
            for t in 1:T
                reserve[r.name, g.name, t] = @variable(model, lower_bound = 0, base_name="reserve[$(r.name),$(g.name),$t]")
            end
        end
    end

    # Define binary variables
    θ = _init(model, :θ)
    for schedule in initial_schedules
        θ[schedule.name] = @variable(model, lower_bound = 0, base_name="theta[$(schedule.name)]")
    end

    coeffs = Dict{String, Dict{Symbol, Union{Vector{Float64},Float64}}}()
    # Compute coefficients for initial schedules
    for schedule in initial_schedules
        C, U, SU, SD, N = _compute_coefficients(instance, schedule)
        coeffs[schedule.name] = Dict(:C => C, :U => U, :SU => SU, :SD => SD, :N => N)
    end
    
    # Define objective function
    @objective(
        model,
        Min,
        sum(
            segprod[g.name, t, k] * g.cost_segments[k].cost[t] 
            for g in sc.thermal_units, t in 1:T, k in 1:length(g.cost_segments)
        ) +
        sum(
            θ[schedule.name] * coeffs[schedule.name][:C] for
            schedule in initial_schedules
        )
    )

    # Define constraints
    eq_prod_above_def = _init(model, :eq_prod_above_def)
    eq_segprod_limit = _init(model, :eq_segprod_limit)
    eq_prod_limit = _init(model, :eq_prod_limit)
    eq_ramp_up = _init(model, :eq_ramp_up)
    eq_ramp_down = _init(model, :eq_ramp_down)
    eq_startup_limit = _init(model, :eq_startup_limit)
    eq_shutdown_limit = _init(model, :eq_shutdown_limit)
    eq_power_balance = _init(model, :eq_power_balance)
    eq_min_spinning_reserve = _init(model, :eq_min_spinning_reserve)
    eq_convexity = _init(model, :eq_convexity)

    for g in sc.thermal_units
        for t in 1:T
            ## eq_prod_above_def
            # original equality constraint
            # eq_prod_above_def[g.name, t] = @constraint(
            #     model,
            #     prod_above[g.name, t] == sum(
            #         segprod[g.name, t, k] for k in 1:length(g.cost_segments)
            #     )
            # )
            #TODO: Check if the greater-than constraints of continuous variables are needed
            eq_prod_above_def[g.name, t, 1] = @constraint(
                model,
                prod_above[g.name, t] >= sum(
                    segprod[g.name, t, k] for k in 1:length(g.cost_segments)
                )
            )
            eq_prod_above_def[g.name, t, 2] = @constraint(
                model,
                -prod_above[g.name, t] >= -sum(
                    segprod[g.name, t, k] for k in 1:length(g.cost_segments)
                )
            )

            ## eq_segprod_limit
            for k in 1:length(g.cost_segments)
                # Similar to the original formulation, add this 
                # as an explicit upper bound on segprod to make the
                # solver's work a bit easier
                # set_upper_bound(
                #     segprod[g.name, t, k],
                #     g.cost_segments[k].mw[t],
                # )

                # original inequality constraint
                eq_segprod_limit[g.name, t, k] = @constraint(
                    model,
                    -segprod[g.name, t, k] >= -g.cost_segments[k].mw[t]
                )
            end

            ## eq_prod_limit
            spinning_reserves = [r for r in g.reserves if r.type == "spinning"]
            total_reserve = 0.0
            if !isempty(spinning_reserves)
                total_reserve += sum(
                    reserve[r.name, g.name, t] for r in spinning_reserves
                )
            end
            eq_prod_limit[g.name, t] = @constraint(
                model,
                -prod_above[g.name, t] - total_reserve >= 
                -sum(
                    coeffs[schedule.name][:U][t] * θ[schedule.name] for
                    schedule in initial_schedules if schedule.unit == g
                )
            )

            ## eq_ramp_up
            # instance with time-invariant min/max power is considered
            # when ramp up/down, do not consider the reserves
            if t == 1
                if g.initial_status > 0
                    eq_ramp_up[g.name, t] = @constraint(
                        model,
                        -g.min_power[t] -
                        prod_above[g.name, t] >=
                        -g.initial_power - g.ramp_up_limit
                    )
                end
            else
                eq_ramp_up[g.name, t] = @constraint(
                    model,
                    -prod_above[g.name, t] + prod_above[g.name, t-1] >= -g.ramp_up_limit
                )
            end

            ## eq_ramp_down
            # instance with time-invariant min/max power is considered
            # when ramp up/down, do not consider the reserves
            if t == 1
                if g.initial_status > 0
                    eq_ramp_down[g.name, t] = @constraint(
                        model,
                        - g.initial_power + 
                        (g.min_power[t] + prod_above[g.name, t]) >= -g.ramp_down_limit
                    )
                end
            else
                eq_ramp_down[g.name, t] = @constraint(
                    model,
                    -prod_above[g.name, t-1] + prod_above[g.name, t] >= -g.ramp_down_limit
                )
            end

            ## eq_startup_limit
            eq_startup_limit[g.name, t] = @constraint(
                model,
                -prod_above[g.name, t] >= -sum(
                    coeffs[schedule.name][:SU][t] * θ[schedule.name] for
                    schedule in initial_schedules if schedule.unit == g
                )
            )

            ## eq_shutdown_limit
            if g.initial_power > g.shutdown_limit
                eq_shutdown_limit[g.name, 0] = @constraint(
                    model,
                    -sum(
                        schedule.switch_off[1] * θ[schedule.name] for
                        schedule in initial_schedules if schedule.unit == g
                    ) >= 0
                )
            end
            if t < T
                eq_shutdown_limit[g.name, t] = @constraint(
                    model,
                    -prod_above[g.name, t] >= -sum(
                        coeffs[schedule.name][:SD][t+1] * θ[schedule.name] for
                        schedule in initial_schedules if schedule.unit == g
                    )
                )
            end

        end
    end

    ## eq_power_balance
    for t in 1:T
        eq_power_balance[t] = @constraint(
            model,
            sum(
                prod_above[g.name, t] for g in sc.thermal_units
            )+
            sum(
                coeffs[schedule.name][:N][t] * θ[schedule.name] for 
                schedule in initial_schedules
            ) >= 
            sum(
                b.load[t] for b in sc.buses
            )
        )
    end 
    
    ## eq_min_spinning_reserve
    for r in sc.reserves
        r.type == "spinning" || continue
        for t in 1:T
            eq_min_spinning_reserve[r.name, t] = @constraint(
                model,
                sum(
                    reserve[r.name, g.name, t] for g in r.thermal_units
                ) >= 
                r.amount[t]
            )
        end
    end

    ## eq_convexity
    for g in sc.thermal_units
       eq_convexity[g.name] = @constraint(
           model,
           -sum(
                θ[schedule.name] for schedule in initial_schedules if schedule.unit == g
           ) >= -1
       )
    end

    return model, θ, coeffs
end

# Initialize the subproblem for each unit
function _initialize_subproblems(
    instance::UnitCommitmentInstance,
    sub_optimizer,
)
    sc = instance.scenarios[1]
    T = instance.time

    # Initialize the subproblems
    subproblems = Dict{String, JuMP.Model}()
    @threads for g in sc.thermal_units
        model = subproblems[g.name] = Model(sub_optimizer)

        # Define binary variables
        var_is_on = _init(model, :var_is_on)
        var_switch_on = _init(model, :var_switch_on)
        var_switch_off = _init(model, :var_switch_off)

        for t in 1:T
            var_is_on[t] = @variable(model, binary=true, base_name="var_is_on[$t]")
            var_switch_on[t] = @variable(model, binary=true, base_name="var_switch_on[$t]")
            var_switch_off[t] = @variable(model, binary=true, base_name="var_switch_off[$t]")
            if g.must_run[t]
                set_lower_bound(var_is_on[t], 1)
            end
        end

        # Define continuous variables
        slack_λ = _init(model, :slack_λ)
        slack_μ_up = _init(model, :slack_μ_up)
        slack_μ_down = _init(model, :slack_μ_down)
        slack_α = _init(model, :slack_α)
        slack_β = _init(model, :slack_β)

        for t in 1:T
            slack_λ[t] = @variable(model, base_name="slack_lambda[$t]")
            slack_μ_up[t] = @variable(model, base_name="slack_mu_up[$t]")
            if t < T
                slack_μ_down[t] = @variable(model, base_name="slack_mu_down[$t]")
            end
            slack_α[t] = @variable(model, base_name="slack_alpha[$t]")
        end
        if g.initial_power > g.shutdown_limit
            slack_μ_down[0] = @variable(model, base_name="slack_mu_down[0]")
        end
        slack_β[1] = @variable(model, base_name="slack_beta")

        # Define objective function
        # For initial subproblems, the dual coefficients are set to 1.
        # In the following solving process, the coefficients will be updated
        @objective(model, Min,
            sum(var_switch_on[t] * g.startup_categories[1].cost for t in 1:T) 
            + sum(var_is_on[t] * g.min_power_cost[t] for t in 1:T)
            - (
                sum(slack_λ[t] * 1 for t in 1:T) +
                sum(slack_μ_up[t] * 1 for t in 1:T) +
                sum(slack_μ_down[t] * 1 for t in 1:T-1) + 
                (g.initial_power > g.shutdown_limit ? slack_μ_down[0] * 1 : 0) +
                sum(slack_α[t] * 1 for t in 1:T) +
                slack_β[1] * 1
            )
        )

        # Define constraints
        # min up/down time constraints
        eq_min_uptime = _init(model, :eq_min_uptime)
        eq_min_downtime = _init(model, :eq_min_downtime)
        for t in 1:T
            eq_min_uptime[t] = @constraint(
                model,
                sum(var_switch_on[i] for i in (t-g.min_uptime+1):t if i >= 1) <= var_is_on[t]
            )
            eq_min_downtime[t] = @constraint(
                model,
                sum(var_switch_off[i] for i in (t-g.min_downtime+1):t if i >= 1) <= 1 - var_is_on[t]
            )
            # initial periods
            if t == 1
                if g.initial_status > 0
                    eq_min_uptime[0] = @constraint(
                        model,
                        sum(
                            var_switch_off[i] for i in 1:(g.min_uptime-g.initial_status) if i <= T
                        ) == 0
                    )
                else
                    eq_min_downtime[0] = @constraint(
                        model,
                        sum(
                            var_switch_on[i] for i in 1:(g.min_downtime+g.initial_status) if i <= T
                        ) == 0
                    )
                end
            end
        end

        # logic constraints
        eq_binary_link = _init(model, :eq_binary_link)
        eq_switch_on_off = _init(model, :eq_switch_on_off)
        for t in 1:T 
            if t == 1
                eq_binary_link[t] = @constraint(
                    model,
                    var_is_on[t] - (g.initial_status > 0 ? 1.0 : 0.0) == var_switch_on[t] - var_switch_off[t]
                )
            else
                eq_binary_link[t] = @constraint(
                    model,
                    var_is_on[t] - var_is_on[t-1] == var_switch_on[t] - var_switch_off[t]
                )
            end
            eq_switch_on_off[t] = @constraint(
                model,
                var_switch_on[t] + var_switch_off[t] <= 1
            )
        end

        # constraints for the dual variables
        eq_def_λ = _init(model, :eq_def_λ)
        eq_def_μ_up = _init(model, :eq_def_μ_up)
        eq_def_μ_down = _init(model, :eq_def_μ_down)
        eq_def_α = _init(model, :eq_def_α)
        eq_def_β = _init(model, :eq_def_β)
        for t in 1:T
            power_diff = max(g.max_power[t], 0.0) - max(g.min_power[t], 0.0)
            if power_diff < 1e-7
                power_diff = 0.0
            end
            eq_def_λ[t] = @constraint(
                model,
                slack_λ[t] == var_is_on[t] * power_diff
            )
            eq_def_μ_up[t] = @constraint(
                model,
                slack_μ_up[t] == (g.max_power[t] - g.min_power[t]) * var_is_on[t] - max(g.max_power[t] - g.startup_limit, 0.0) * var_switch_on[t]
            )
            if t < T
                eq_def_μ_down[t] = @constraint(
                    model,
                    slack_μ_down[t] == (g.max_power[t] - g.min_power[t]) * var_is_on[t] - max(g.max_power[t] - g.shutdown_limit, 0.0) * var_switch_off[t+1]
                )
            end
            eq_def_α[t] = @constraint(
                model,
                slack_α[t] == g.min_power[t] * var_is_on[t]
            )
        end
        if g.initial_power > g.shutdown_limit
            eq_def_μ_down[0] = @constraint(
                model,
                slack_μ_down[0] == -1
            )
        end
        eq_def_β = @constraint(
            model,
            slack_β[1] == -1
        )
    end
    

    return subproblems
end

# Solve the subproblems
function _solve_subproblems(
    instance::UnitCommitmentInstance,
    dual_values::Tuple{Dict, Dict, Dict, Dict, Dict},
    subproblems::Dict{String, JuMP.Model},
    initial_schedules::Vector{_Schedule},
)
    sc = instance.scenarios[1]
    T = instance.time

    λ, μ_up, μ_down, α, β = dual_values
    
    reduced_costs = Dict{String, Float64}()
    new_schedules = Vector{Union{Nothing, _Schedule}}(nothing, length(sc.thermal_units))

    thermal_units_enumerated = collect(enumerate(sc.thermal_units))
    # println("Entering the parallel loop")
    @threads for (i, g) in thermal_units_enumerated
        gn = g.name
        # get dual values of each unit
        unit_λ = Dict(t => λ[gn, t] for t in 1:T if (gn, t) in keys(λ))
        unit_μ_up = Dict(t => μ_up[gn, t] for t in 1:T if (gn, t) in keys(μ_up))
        unit_μ_down = Dict(t => μ_down[gn, t] for t in 0:T-1 if (gn, t) in keys(μ_down))
        unit_α = Dict(t => α[t] for t in 1:T if t in keys(α))
        unit_β = β[gn]


        sp = subproblems[gn]
        var_switch_on = sp[:var_switch_on]
        var_is_on = sp[:var_is_on]
        slack_λ = sp[:slack_λ]
        slack_μ_up = sp[:slack_μ_up]
        slack_μ_down = sp[:slack_μ_down]
        slack_α = sp[:slack_α]
        slack_β = sp[:slack_β]

        # Update the coefficients of objective function
        @objective(sp, Min,
        sum(var_switch_on[t] * g.startup_categories[1].cost for t in 1:T) 
        + sum(var_is_on[t] * g.min_power_cost[t] for t in 1:T)
        - (
            sum(slack_λ[t] * unit_λ[t] for t in 1:T) +
            sum(slack_μ_up[t] * unit_μ_up[t] for t in 1:T) +
            sum(slack_μ_down[t] * unit_μ_down[t] for t in 1:T-1) + 
            (g.initial_power > g.shutdown_limit ? slack_μ_down[0] * unit_μ_down[0] : 0) +
            sum(slack_α[t] * unit_α[t] for t in 1:T) +
            slack_β[1] * unit_β
        )
        )
       
        # Optimize the subproblem
        JuMP.optimize!(sp)

        if termination_status(sp) == MOI.OPTIMAL
            # println("Subproblem for $(g.name) is solved to optimality")
            w = Vector{Int}(undef, T)
            for t in 1:T
                w[t] = round(Int, value(sp[:var_is_on][t]))
            end
            is_on, switch_on, switch_off = _generate_state_from_schedule(instance, g, w)
            name = "$(g.name)_$(_count_schedule_index(initial_schedules, g))"
            schedule = _Schedule(name, g, w, is_on, switch_on, switch_off)
            reduced_cost = objective_value(sp)
            if reduced_cost <= -1e-6
                if !_is_schedule_exist(initial_schedules, schedule)
                    # if the schedule does not exist and the reduced cost is negative
                    new_schedules[i] = schedule
                    reduced_costs[g.name] = reduced_cost
                else
                    new_schedules[i] = nothing
                    #TODO: Check if error should be throw out
                    error("The schedule of unit $(g.name) with negative reduced cost already exists")
                end
            else
                new_schedules[i] = nothing
                reduced_costs[g.name] = reduced_cost
                # println("All schedules of unit $(g.name) satisfy optimal conditions")
            end
            # if !_is_schedule_exist(initial_schedules, schedule) && reduced_cost <= -1e-6
            #     # if the schedule does not exist and the reduced cost is negative
            #     new_schedules[i] = schedule
            #     reduced_costs[g.name] = objective_value(sp)
            # elseif _is_schedule_exist(initial_schedules, schedule) && reduced_cost <= -1e-6
            #     new_schedules[i] = nothing
            #     #TODO: Check if error should be throw out
            #     error("The schedule of unit $(g.name) already exists")
            # end
        else
            # It is werid that a finite feasible region yields a dual infeasible problem.
            #TODO: Check if error should be throw out
            # println("Subproblem for $(g.name) is not solved to optimality")
            error("Subproblem for $(g.name) is not solved to optimality")
            println("Termination status: ", termination_status(sp))
            reduced_costs[g.name] = -Inf
        end    
    end

    return new_schedules, reduced_costs

end

# Compute the coefficients for schedules
function _compute_coefficients(
    instance::UnitCommitmentInstance,
    schedule::_Schedule,
)
    sc = instance.scenarios[1]
    T = instance.time

    # Compute the cost of the schedule
    C = 0.0
    for t in 1:T
        C += schedule.switch_on[t] * schedule.unit.startup_categories[1].cost
        C += schedule.is_on[t] * schedule.unit.min_power_cost[t]
    end

    # Compute the coefficients for eq_prod_limit in the original formulation
    U = zeros(T)
    for t in 1:T
        power_diff = max(schedule.unit.max_power[t], 0.0) - max(schedule.unit.min_power[t], 0.0)
        if power_diff < 1e-7
            power_diff = 0.0
        end
        U[t] = schedule.is_on[t] * power_diff
    end

    # Compute the coefficients for eq_startup_limit in the original formulation
    SU = zeros(T)
    for t in 1:T
        SU[t] = (schedule.unit.max_power[t] - schedule.unit.min_power[t]) * schedule.is_on[t] - max(schedule.unit.max_power[t] - schedule.unit.startup_limit, 0.0) * schedule.switch_on[t]
    end

    # Compute the coefficients for eq_shutdown_limit in the original formulation
    SD = zeros(T)
    for t in 1:T
        if t == 1
            # when t = 1 and g.initial_power > g.shutdown_limit, switch_off[1] = 0
            SD[t] = - schedule.switch_off[1] 
        else
            # be careful with the indexing
            ti = t - 1
            SD[t] = (schedule.unit.max_power[ti] - schedule.unit.min_power[ti]) * schedule.is_on[ti] - max(schedule.unit.max_power[ti] - schedule.unit.shutdown_limit, 0.0) * schedule.switch_off[ti+1]
        end
        
    end
    
    # Compute the coefficients for eq_net_injection & eq_power_balance in the original formulation
    N = zeros(T)
    for t in 1:T
        N[t] = schedule.unit.min_power[t] * schedule.is_on[t]
    end

    return (C = C, U = U, SU = SU, SD = SD, N = N)
end

# Check if the schedule exists in the list
function _is_schedule_exist(
    schedules::Vector{_Schedule},
    schedule::_Schedule,
)::Bool
    return any(s -> s.unit == schedule.unit && s.w == schedule.w, schedules)
end

# Get the dual values of RMP
function _get_dual_values(
    instance::UnitCommitmentInstance,
    model::JuMP.Model,
)
    # Initialize the dual values
    λ = Dict()
    μ_up = Dict()
    μ_down = Dict()
    α = Dict()
    β = Dict()

    # Get the instance information and the constraints
    sc = instance.scenarios[1]
    T = instance.time
    eq_prod_limit = model[:eq_prod_limit]
    eq_startup_limit = model[:eq_startup_limit]
    eq_shutdown_limit = model[:eq_shutdown_limit]
    eq_power_balance = model[:eq_power_balance]
    eq_convexity = model[:eq_convexity]

    # Get the dual values
    for g in sc.thermal_units
        if g.initial_power > g.shutdown_limit   
            μ_down[g.name, 0] = dual(eq_shutdown_limit[g.name, 0])
        end
        for t in 1:T
            λ[g.name, t] = dual(eq_prod_limit[g.name, t])
            μ_up[g.name, t] = dual(eq_startup_limit[g.name, t])
            if t < T
                μ_down[g.name, t] = dual(eq_shutdown_limit[g.name, t])
            end
        end
    end

    for t in 1:T
        α[t] = dual(eq_power_balance[t])
    end

    for g in sc.thermal_units
        β[g.name] = dual(eq_convexity[g.name])
    end

    return λ, μ_up, μ_down, α, β
end

