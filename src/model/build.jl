# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

using JuMP, MathOptInterface, DataStructures
import JuMP: value, fix, set_name

"""
    function build_model(;
        instance::UnitCommitmentInstance,
        optimizer = nothing,
        formulation = Formulation(),
        variable_names::Bool = false,
    )::JuMP.Model

Build the JuMP model corresponding to the given unit commitment instance.

Arguments
---------

- `instance`:
    the instance.
- `optimizer`:
    the optimizer factory that should be attached to this model (e.g. Cbc.Optimizer).
    If not provided, no optimizer will be attached.
- `formulation`:
    the MIP formulation to use. By default, uses a formulation that combines
    modeling components from different publications that provides good
    performance across a wide variety of instances. An alternative formulation
    may also be provided.
- `variable_names`: 
    if true, set variable and constraint names. Important if the model is going
    to be exported to an MPS file. For large models, this can take significant
    time, so it's disabled by default.

Examples
--------

```julia
# Read benchmark instance
instance = UnitCommitment.read_benchmark("matpower/case118/2017-02-01")

# Construct model (using state-of-the-art defaults)
model = UnitCommitment.build_model(
    instance = instance,
    optimizer = Cbc.Optimizer,
)

# Construct model (using customized formulation)
model = UnitCommitment.build_model(
    instance = instance,
    optimizer = Cbc.Optimizer,
    formulation = Formulation(
        pwl_costs = KnuOstWat2018.PwlCosts(),
        ramping = MorLatRam2013.Ramping(),
        startup_costs = MorLatRam2013.StartupCosts(),
        transmission = ShiftFactorsFormulation(
            isf_cutoff = 0.005,
            lodf_cutoff = 0.001,
        ),
    ),
)
```

"""
function build_model(;
    instance::UnitCommitmentInstance,
    optimizer = nothing,
    formulation = Formulation(),
    variable_names::Bool = false,
)::JuMP.Model
    @info "Building model..."
    time_model = @elapsed begin
        model = Model()
        if optimizer !== nothing
            set_optimizer(model, optimizer)
        end
        model[:obj] = AffExpr()
        model[:instance] = instance
        for g in instance.scenarios[1].thermal_units
            _add_unit_commitment!(model, g, formulation)
        end
        for sc in instance.scenarios
            @info "Building scenario $(sc.name) with " *
                  "probability $(sc.probability)"
            _setup_transmission(formulation.transmission, sc)
            for l in sc.lines
                _add_transmission_line!(model, l, formulation.transmission, sc)
            end
            for b in sc.buses
                _add_bus!(model, b, sc)
            end
            for ps in sc.price_sensitive_loads
                _add_price_sensitive_load!(model, ps, sc)
            end
            for g in sc.thermal_units
                _add_unit_dispatch!(model, g, formulation, sc)
            end
            for pu in sc.profiled_units
                _add_profiled_unit!(model, pu, sc)
            end
            for su in sc.storage_units
                _add_storage_unit!(model, su, sc)
            end
            _add_system_wide_eqs!(model, sc)
        end
        @objective(model, Min, model[:obj])
    end
    @info @sprintf("Built model in %.2f seconds", time_model)
    if variable_names
        _set_names!(model)
    end
    return model
end

# modified model by Yu-Yang Tang
function build_mymodel(;
    instance::UnitCommitmentInstance,
    optimizer = nothing,
    formulation = Formulation(
        pwl_costs=Gar1962.PwlCosts(),   # here we use the classic piecewise costs
    ),
    variable_names::Bool = false,
    is_power_surplus_allowed::Bool = true,
    is_min_updown::Bool = true,
    is_pre_contingency::Bool = true,
    is_post_contingency::Bool = false,
)::JuMP.Model
    @info "Building modified model..."
    ins_param = _rare_instance_check(instance)
    time_model = @elapsed begin
        model = Model()
        if optimizer !== nothing
            set_optimizer(model, optimizer)
        end
        model[:obj] = AffExpr()
        model[:instance] = instance
        statistic = UnitCommitment.Statistic()
        model[:statistic] = statistic
        statistic.ins_info = _memorize_ins_info(ins_param)
        # assigning whether to consider reserve in the ramping constraints
        model[:RESERVES_WHEN_START_UP] = false
        model[:RESERVES_WHEN_RAMP_UP] = false
        model[:RESERVES_WHEN_RAMP_DOWN] = false
        model[:RESERVES_WHEN_SHUT_DOWN] = false
        all_t_pre_cont::Float64 = 0
        all_t_post_cont::Float64 = 0
        for g in instance.scenarios[1].thermal_units
            _add_no_startup_delay_cost_unit_commitment!(model, g, formulation, is_min_updown)
        end
        for sc in instance.scenarios
            @info "Building scenario $(sc.name) with " *
                  "probability $(sc.probability)"
            _setup_transmission(formulation.transmission, sc)
            for l in sc.lines
                _add_restricted_transmission_line!(model, l, formulation.transmission, sc)
            end
            for b in sc.buses
                _add_no_curtail_bus!(model, b, sc)
            end
            # for ps in sc.price_sensitive_loads
            #     _add_price_sensitive_load!(model, ps, sc)
            # end
            for g in sc.thermal_units
                _add_unit_dispatch!(model, g, formulation, sc)
            end
            # for pu in sc.profiled_units
            #     _add_profiled_unit!(model, pu, sc)
            # end
            # for su in sc.storage_units
            #     _add_storage_unit!(model, su, sc)
            # end
            _add_system_wide_eqs!(model, sc, is_power_surplus_allowed=is_power_surplus_allowed)
            if is_pre_contingency
                time_add_pre_conting = @elapsed begin
                    _add_pre_contingency_constraints!(model, sc)
                end
                @info @sprintf("Add pre-contingency security constraints in %.2f seconds", time_add_pre_conting)
                all_t_pre_cont += time_add_pre_conting
            end
            if is_post_contingency
                time_add_post_conting = @elapsed begin
                    _add_post_contingency_constraints!(model, sc)
                end
                @info @sprintf("Add post-contingency security constraints in %.2f seconds", time_add_post_conting)
                all_t_post_cont += time_add_post_conting
            end
        end
        @objective(model, Min, model[:obj])
    end
    @info @sprintf("Built modified model in %.2f seconds", time_model)
    statistic.time_build_model["t_pre_cont"] = all_t_pre_cont
    statistic.time_build_model["t_post_cont"] = all_t_post_cont
    statistic.time_build_model["time"] = time_model

    if variable_names
        _set_names!(model)
    end
    return model
end

function _rare_instance_check(
    instance::UnitCommitmentInstance
)
    detected_issues = Set{String}()
    is_commit_empty = true
    is_must_run_empty = true
    is_negative_penalty = true
    is_min_power_consist = true
    is_single_startup = true
    can_init_on = true

    for unit in instance.scenarios[1].thermal_units
        # Check if commitment_status has any non-nothing value
        if any(x -> x !== nothing, unit.commitment_status)
            if "unit commitment status not empty" ∉ detected_issues
                @info "Rare instance detected: unit commitment status is not empty"
                push!(detected_issues, "unit commitment status not empty")
                is_commit_empty = false
            end
        end

        # Check if must_run contains any true value
        if !all(!, unit.must_run)
            if "must run not empty" ∉ detected_issues
                @info "Rare instance detected: must run is not empty"
                push!(detected_issues, "must run not empty")
                is_must_run_empty = false
            end
        end

        # Check if any reserve has a positive shortfall penalty
        for r in unit.reserves
            if r.shortfall_penalty > 0
                if "positive shortfall penalty" ∉ detected_issues
                    @info "Rare instance detected: positive shortfall penalty"
                    push!(detected_issues, "positive shortfall penalty")
                    is_negative_penalty = false
                end
            end
        end

        # Check if there is a time-variant discontinuity in min_power and max_power
        for t in 1:instance.time - 1
            if unit.min_power[t+1] - unit.min_power[t] > 1e-6
                if "time-variant min power" ∉ detected_issues
                    @info "Rare instance detected: time-variant min power"
                    push!(detected_issues, "time-variant min power")
                    is_min_power_consist = false
                end
            end
        end

        # Check if the unit has multiple startup categories
        if length(unit.startup_categories) > 1
            if "multiple startup categories" ∉ detected_issues
                @info "Rare instance detected: multiple startup categories"
                push!(detected_issues, "multiple startup categories")
                is_single_startup = false
            end
        end

        # Check if the state of the unit at the first period can be turned on
        if unit.initial_status < 0 && unit.min_downtime + unit.initial_status > 0
            if "initial status cannot be on due to min_downtime constraints" ∉ detected_issues
                @info "Rare instance detected: initial status cannot be on due to min_downtime constraints"
                push!(detected_issues, "initial status cannot be on due to min_downtime constraints")
                can_init_on = false
            end
        end
    end

    return is_commit_empty, is_must_run_empty, is_negative_penalty, is_min_power_consist, is_single_startup, can_init_on
end

function _memorize_ins_info(ins_param)
    is_commit_empty, is_must_run_empty, is_negative_penalty, is_min_power_consist, is_single_startup, can_init_on = ins_param
    ins_info = []
    if !is_commit_empty
        push!(ins_info, "unit commitment status not empty")
    end
    if !is_must_run_empty
        push!(ins_info, "must run not empty")
    end
    if !is_negative_penalty
        push!(ins_info, "positive shortfall penalty")
    end
    if !is_min_power_consist
        push!(ins_info, "time-variant min power")
    end
    if !is_single_startup
        push!(ins_info, "multiple startup categories")
    end
    if !can_init_on
        push!(ins_info, "status 1 cannot be on due to min_downtime")
    end

    return ins_info

end