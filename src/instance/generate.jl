using Random, JSON, DataStructures

function generate_instance(;
    num_instance::Int=20,
    folder::String="../instances/generated/",
    filename::String="uc_instance",
    seed::Int=12345,
    num_units::Int=10,
    num_buses::Int=1,
    num_periods::Int=96,
    is_single_bus::Bool=true,
)
    Random.seed!(seed)

    for i in 1:num_instance
        instance_seed = rand(1:1000000)
        if is_single_bus
            data = _generate_data(
                num_units=num_units,
                num_buses=num_buses,
                num_periods=num_periods,
                seed=instance_seed,
            )
            filepath = joinpath(folder, "$filename-$i.json")
            mkpath(dirname(filepath))  # Ensure the directory exists
            open(filepath, "w") do io
                JSON.print(io, data, 2)
            end
            println("Instance $i generated and saved in $folder")
        else
            #TODO: Implement multi-bus generating function

        end





    end




    








end

function _generate_data(;
    num_units::Int,
    num_buses::Int,
    num_periods::Int,
    seed::Int,
)
    rng = MersenneTwister(seed)

    # define a single bus
    bus_name = "b1"


    # generate generators
    generators = OrderedDict(
        "g$i" => begin
        prod_curve = _generate_production_curve(rng, 800.0, 1000.0)  # Generate MW curve
        cost_curve = _generate_cost_curve(rng, 5000.0, 10000.0)  # Generate $ cost curve
        ramp_limit = 0.24 * prod_curve[end]  
        startup_limit = 0.2 * prod_curve[end]
        shutdown_limit = 0.28 * prod_curve[end]
        min_uptime = rand(rng, 1:60)
        min_downtime = rand(rng, 1:60)
        init_status = rand(rng, vcat(-96:-min_downtime, 1:96)) # ensure init_status != 0 and unit can be turn on at period 1
        init_power = (init_status > 0) ? rand(rng, prod_curve[1]:prod_curve[end]) : 0.0

        OrderedDict(
            "Bus" => bus_name,  # All generators are connected to the single bus
            "Production cost curve (MW)" => prod_curve,
            "Production cost curve (\$)" => cost_curve,
            "Startup costs (\$)" => [rand(rng, 1000:5000)],
            "Startup delays (h)" => [1],
            "Ramp up limit (MW)" => ramp_limit,
            "Ramp down limit (MW)" => ramp_limit,  
            "Startup limit (MW)" => startup_limit,
            "Shutdown limit (MW)" => shutdown_limit,
            "Minimum uptime (h)" => min_uptime,
            "Minimum downtime (h)" => min_downtime,
            "Reserve eligibility" => ["r1"],
            "Initial status (h)" => init_status,
            "Initial power (MW)" => init_power,
        )
    end for i in 1:num_units
    )
    
    # generate the bus
    total_capacity = sum(generators["g$(i)"]["Production cost curve (MW)"][end] for i in 1:num_units)
    buses = OrderedDict(
        bus_name => OrderedDict(
            "Load (MW)" => _generate_demand(rng, num_periods, total_capacity),
        )
    )

    # generate reserves
    reserves = OrderedDict(
        "r1" => OrderedDict(
            "Type" => "Spinning",
            "Amount (MW)" => 0.1 .* buses["b1"]["Load (MW)"],
        )
    )
    

   # generate json structure without network topology
   uc_data = OrderedDict(
        "SOURCE" => "Generated using UnitCommitment.jl - Single Bus System",
        "Parameters" => OrderedDict(
            "Version" => "0.3", 
            "Power balance penalty (\$/MW)" => 1000.0, 
            "Time horizon (h)" => num_periods
        ),
        "Generators" => generators,
        "Buses" => buses,
        "Reserves" => reserves,
    )

    return uc_data
end

function _generate_demand(rng, num_periods, total_capacity)
    #TODO: design fucntion for all kinds
    # Define usage ranges
    usage_ranges = [
        (0, 4, 0.1, 0.25),    # Midnight (00:00-01:00)
        (4, 8, 0.1, 0.25),    # Early morning low demand (01:00-02:00)
        (8, 16, 0.05, 0.25),  # Late night to morning (02:00-04:00)
        (16, 24, 0.1, 0.3),   # Morning wake-up period (04:00-06:00)
        (24, 30, 0.15, 0.4),  # Start of morning peak (06:00-07:30)
        (30, 36, 0.2, 0.45),  # Morning peak hours (07:30-09:00)
        (36, 42, 0.2, 0.5),   # End of morning peak (09:00-10:30)
        (42, 48, 0.15, 0.45), # Late morning work period (10:30-12:00)
        (48, 54, 0.20, 0.50), # Lunch break (12:00-13:30)
        (54, 60, 0.15, 0.40), # Early afternoon period (13:30-15:00)
        (60, 66, 0.20, 0.45), # Afternoon work period (15:00-16:30)
        (66, 72, 0.25, 0.55), # Start of evening peak (16:30-18:00)
        (72, 78, 0.20, 0.50), # Evening peak (18:00-19:30)
        (78, 84, 0.25, 0.55), # Nighttime high demand period (19:30-21:00)
        (84, 90, 0.25, 0.40), # Late night period (21:00-22:30)
        (90, 96, 0.15, 0.25), # Pre-midnight (22:30-00:00)
    ]
    demand = zeros(num_periods)

    for t in 1:num_periods
        # Calculate the current time point corresponding to the 96 interval index
        interval_index = Int(floor((t - 1) * 96 / num_periods))

        # Find the corresponding usage range
        for (start, end_, min_factor, max_factor) in usage_ranges
            if start <= interval_index < end_
                # Calculate the mean factor
                mean_factor = (min_factor + max_factor) / 2
                
                # Calculate the base demand
                base_demand = mean_factor * total_capacity
                
                # Vary the demand by up to 15% higher or lower
                variation = (rand(rng) * 0.3) - 0.15  # Random number between -0.15 and 0.15
                demand[t] = base_demand * (1 + variation)
                
                break
            end
        end
    end
    
    return round.(demand, digits=2)
end

function _generate_production_curve(rng, range_down, range_up)
    Pmax = rand(rng, range_down:range_up)
    Pmin = 0.15 * Pmax

    # Divide the range [Pmin, Pmax] into 5 equal segments
    production_curve = range(Pmin, Pmax, length=5) |> collect
    
    return production_curve
end

function _generate_cost_curve(rng, range_down, range_up)
    # Generate Pmax cost randomly within the given range
    Pmax_cost = rand(rng, range_down:range_up)
    Pmin_cost = 0.1 * Pmax_cost  # Assume Pmin cost is 50% of Pmax cost

    # Define increasing slopes (each segment has a larger increase than the previous one)
    base_slope = (Pmax_cost - Pmin_cost) / 10  # Base slope step size
    slopes = [base_slope * (1 + i * 0.5) for i in 0:3]  # Gradually increasing slopes

    # Initialize the cost curve with the first cost (Pmin_cost)
    cost_curve = [Pmin_cost]

    # Generate the remaining cost points with increasing slopes
    for i in 1:4
        next_cost = cost_curve[end] + slopes[i]
        push!(cost_curve, next_cost)
    end



    return cost_curve
end
