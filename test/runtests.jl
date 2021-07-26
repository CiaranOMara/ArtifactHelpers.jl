using Test
using Pkg
using Pkg.Artifacts
using ArtifactHelpers

@testset "ArtifactHelpers" begin

    artifacts_toml = touch(joinpath(@__DIR__, "Artifacts.toml"))

    artifacts_dir = mkpath(joinpath(@__DIR__, "tmp_artifacts"))

    Pkg.Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_dir

    function test_process(entry::Processed; force::Bool = false, verbose::Bool = false)

        tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.
            write(joinpath(path_artifact, "test1.txt"), "test1")
            write(joinpath(path_artifact, "test2.txt"), "test2")
        end

        return tree_hash
    end

    @testset "Helpers" begin
        @test ArtifactHelpers.isurl("http") == true
        @test ArtifactHelpers.isurl("https") == true
        @test ArtifactHelpers.isurl("https://") == true
        @test ArtifactHelpers.isurl("htt") == false

        #Check setindex!.
        entry = Processed("test")
        change = setindex!(entry, "test", "test")
        @test ArtifactHelpers.metadata(entry) == change

    end #testset "Helpers"

    @testset "Building" begin
        @test_nowarn build_artifact!(artifacts_toml, File("http://hgdownload.cse.ucsc.edu/goldenPath/mm10/bigZips/mm10.chrom.sizes"), force = true, verbose = false)#TODO: host or find reasonable download.

        @test_nowarn build_artifact!(artifacts_toml, Zip("https://github.com/usadellab/Trimmomatic/files/5854859/Trimmomatic-0.39.zip"), force = true, verbose = false) #TODO: host or find reasonable download.

        @test_nowarn build_artifact!(artifacts_toml, AutoDownloadable("http://hgdownload.cse.ucsc.edu/goldenPath/mm10/bigZips/chromAgp.tar.gz"), force = true, verbose = false)#TODO: host or find reasonable download.

        @test_nowarn build_artifact!(artifacts_toml, Processed("Processed"), test_process, force = true, verbose = false)

        @test_nowarn build_artifact!(artifacts_toml, Processed("ProcessedDo"), force = true, verbose = false) do path_artifact
            write(joinpath(path_artifact, "test.txt"), "test")
        end

    end #testset "Binding"

    @testset "Initialise with artifacts present" begin

        @test initialise_artifact(artifacts_toml, "mm10.chrom.sizes") == artifact_hash("mm10.chrom.sizes", artifacts_toml)

        @test initialise_artifact(artifacts_toml, "Trimmomatic-0.39.zip") == artifact_hash("Trimmomatic-0.39.zip", artifacts_toml)

        @test initialise_artifact(artifacts_toml, "chromAgp.tar.gz") == artifact_hash("chromAgp.tar.gz", artifacts_toml)

        @test initialise_artifact(artifacts_toml, "Processed", test_process) == artifact_hash("Processed", artifacts_toml)

    end #testest "Initialise with artifacts present"

    @testset "Initialise without artifacts present" begin
        artifacts = joinpath.(artifacts_dir, readdir(artifacts_dir))
        rm.(artifacts,recursive = true)

        @test initialise_artifact(artifacts_toml, "mm10.chrom.sizes") == artifact_hash("mm10.chrom.sizes", artifacts_toml)

        @test initialise_artifact(artifacts_toml, "Trimmomatic-0.39.zip") == artifact_hash("Trimmomatic-0.39.zip", artifacts_toml)

        @test initialise_artifact(artifacts_toml, "chromAgp.tar.gz") == artifact_hash("chromAgp.tar.gz", artifacts_toml)

        @test initialise_artifact(artifacts_toml, "Processed", test_process) == artifact_hash("Processed", artifacts_toml)

    end #testset "Initialise without artifacts present"

    @testset "Initialise without Artifacts.toml present" begin
        rm(artifacts_toml)
        rm(artifacts_dir, recursive = true) #Note: may aswell clean up.

        # Check fallthrough.

        @test_logs (:warn, "Artifacts.toml does not exist at specified path.") initialise_artifact(artifacts_toml, "something")

        touch(artifacts_toml)

        @test_logs (:warn, "An artifact entry for \"something\" does not exist in Artifacts.toml.") initialise_artifact(artifacts_toml, "something")

        rm(artifacts_toml) # Final clean up.

    end #testset "Initialise without artifacts present"


end # testset ArtifactHelpers
