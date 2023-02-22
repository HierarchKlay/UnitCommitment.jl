# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

using UnitCommitment, LinearAlgebra, Cbc, JuMP, JSON, GZip

@testset "read v0.2" begin
    instance = UnitCommitment.read("$FIXTURES/ucjl-0.2.json.gz")
    for sc in instance.scenarios
        @test length(sc.reserves_by_name["r1"].amount) == 4
        @test sc.units_by_name["g2"].reserves[1].name == "r1"
    end
end

@testset "read v0.3" begin
    instance = UnitCommitment.read("$FIXTURES/ucjl-0.3.json.gz")
    for sc in instance.scenarios
        @test length(sc.units) == 6
        @test length(sc.buses) == 14
        @test length(sc.lines) == 20
    end
end
