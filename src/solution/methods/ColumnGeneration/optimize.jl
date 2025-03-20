using JuMP, MathOptInterface
using Base.Threads

function optimize!(instance::UnitCommitmentInstance, method::ColumnGeneration.Method)
    # Set gap and turn off output
    master_optimizer = _setup_user_optimizer(method.master_params.solver, 0, method.master_params.time_limit, method.master_params.gap_limit)
    sub_optimizer = _setup_user_optimizer(method.sub_params.solver, 0, method.sub_params.time_limit, method.sub_params.gap_limit)
    # @info "optimizer setup done"
    method.statistic = UnitCommitment.Statistic()
    ins_param = _rare_instance_check(instance)
    method.statistic.ins_info = _memorize_ins_info(ins_param)
    stat = method.statistic
    stat.method = method
    stat.time_build_model["t_build_rmp"] = 0.0
    stat.others.cg["schedule_solutions"] = OrderedDict()
    # @info "statistic setup done"
    # Generate initial schedules
    can_init_on = ins_param[6]
    gen_init_sched_time = @elapsed begin
        initial_schedules = _generate_initial_schedules(instance, can_init_on)
    end
    stat.time_build_model["t_gen_init_sched"] = gen_init_sched_time
    stat.time_build_model["t_build_rmp"] += gen_init_sched_time
    
    @info "initial schedules generated"
    # whether to use aggregated θ or not
    is_aggr_θ = false

    # Column generation algorithm
    rmp, final_schedules, θ, stat = _column_generation(instance, initial_schedules, master_optimizer, sub_optimizer, is_aggr_θ, stat)
    @info "column generation done"
    # Dubugging
    # println("# of units: $(length(instance.scenarios[1].thermal_units))")
    # println("# of schedules: $(length(final_schedules))")
    println("final RMP objective value: $(objective_value(rmp))")
    # println("θ: $(θ)")
    # for g in instance.scenarios[1].thermal_units
    #     sn = "$(g.name)_1"
    #     println("θ[$(sn)] = $(value(θ[sn]))")
    # end

    # Large neighborhood search based on RMP
    # set θ to binary
    for (sn, var) in θ
        set_binary(var)
    end

    # Enable output
    #TODO: absorb the following code into _setup_user_optimizer
    LNS_optimizer = _setup_user_optimizer(method.master_params.solver, 1, 7200, 1e-4)
    set_time_limit_sec(rmp, 900.0)
    set_optimizer(rmp, LNS_optimizer)
    stat.time_solve_model["t_solve_mip"] = @elapsed begin
        JuMP.optimize!(rmp)    
    end
    
    # Debugging
    println("Objective value: $(objective_value(rmp))")
    for (sn, var) in θ
        if value(var) > 0.5
            for schedule in final_schedules
                if schedule.name == sn
                    # println("$(sn): $(schedule.w)")
                    # println("value: $(value(var))")
                    stat.others.cg["schedule_solutions"][schedule.unit.name] = schedule.w
                end
            end
        end
    end
    stat.obj = objective_value(rmp)
    stat.gap = relative_gap(rmp)
    stat.num_node = node_count(rmp)
    return stat, rmp
end

# Generate initial schedules for RMP
function _generate_initial_schedules(
    instance::UnitCommitmentInstance,
    can_init_on::Bool,
)::Vector{_Schedule}
    T = instance.time
    initial_schedules = Vector{_Schedule}()
    
    if can_init_on
        # Generate initial schedule with all generators on for all time periods
        for unit in instance.scenarios[1].thermal_units
            w = ones(Int, T)
            is_on, switch_on, switch_off = _generate_state_from_schedule(instance, unit, w)
            name = "$(unit.name)_1"
            push!(initial_schedules, _Schedule(name, unit, w, is_on, switch_on, switch_off))
            # w = zeros(Int, T)
            # is_on, switch_on, switch_off = _generate_state_from_schedule(instance, unit, w)
            # name = "$(unit.name)_2"
            # push!(initial_schedules, _Schedule(name, unit, w, is_on, switch_on, switch_off))
        end
    else
        # Generate initial schedule with all generators on for all time periods permitted by the initial status and min down time
        for unit in instance.scenarios[1].thermal_units
            w = ones(Int, T)
            if unit.initial_status < 0 
                # If the initial status is off, the generator shall be off until the min down time is satisfied
                for t in 1:(unit.min_downtime+unit.initial_status) 
                    w[t] = 0
                end
            end
            is_on, switch_on, switch_off = _generate_state_from_schedule(instance, unit, w)
            name = "$(unit.name)_1"
            push!(initial_schedules, _Schedule(name, unit, w, is_on, switch_on, switch_off))
        end
    end

    return initial_schedules
end

# Generate state values based on the schedule
function _generate_state_from_schedule(
    instance::UnitCommitmentInstance,
    unit::ThermalUnit,
    w::Vector{Int},
)::Tuple{Vector{Int}, Vector{Int}, Vector{Int}}
    is_on = w
    switch_on = zeros(Int, instance.time)
    switch_off = zeros(Int, instance.time)

    if unit.initial_power === nothing || unit.initial_status === nothing
        error("Initial conditions for $(unit.name) must be provided")
    end
    
    for t in 1:instance.time
        if t == 1
            switch_on[t] = max(0, w[t] - (unit.initial_status > 0 ? 1 : 0))
            switch_off[t] = max(0, (unit.initial_status > 0 ? 1 : 0) - w[t])
        else
            switch_on[t] = max(0, w[t] - w[t-1])
            switch_off[t] = max(0, w[t-1] - w[t])
        end
    end

    return is_on, switch_on, switch_off
    
end

# Count the index of a new schedule of a unit
function _count_schedule_index(
    schedules::Vector{_Schedule},
    unit::ThermalUnit,
)::Int
    i = count(schedule -> schedule.unit == unit, schedules)
    return i+1
end

# Create an optimizer according to the params
function _setup_user_optimizer(solver, is_output, time_limit, gap)
    if occursin("CPLEX", string(solver))
        return optimizer_with_attributes(
        solver,
        "CPX_PARAM_SCRIND" => is_output,
        "CPX_PARAM_TILIM" => time_limit,
        "CPX_PARAM_EPGAP" => gap,
        )
    elseif occursin("Gurobi", string(solver))
        return optimizer_with_attributes(
        solver,
        "OutputFlag" => is_output,
        "TimeLimit" => time_limit,
        "MIPGap" => gap,
        )
    else
        error("Invalid solver specified. Use 'CPLEX' or 'Gurobi'.")
    end
end
