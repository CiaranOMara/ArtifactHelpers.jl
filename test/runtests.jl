using Test
using ArtifactHelpers

@testset "ArtifactHelpers" begin

    artifacts_toml = touch(joinpath(@__DIR__, "Artifacts.toml"))

    #TODO: location for test artifacts.

    @testset "File - plain" begin
        #TODO: host or find reasonable download.
    end

    @testset "File - .tar.gz" begin
        #TODO: host or find reasonable download.

    end

    @testset "Processed" begin

    end

    rm(artifacts_toml)

end # testset ArtifactHelpers
