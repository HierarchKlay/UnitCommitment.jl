using UnitCommitment, DataStructures, JSON

T = [24, 48, 96]
G = [100, 500, 1000, 1500, 2000, 4000]

base_path = "/share/home/tangyuyang/tyyGit/UnitCommitment.jl"
for t in T
    for g in G
        instance = UnitCommitment.generate_instance(
            num_instance=5,
            folder=joinpath(base_path, "instances/generated/"),
            filename="$(g)g_$(t)t",
            num_units=g,
            num_periods=t,
        )
    end
end