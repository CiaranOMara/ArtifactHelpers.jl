module ArtifactHelpers

using Pkg
using Pkg.Artifacts
using Pkg.PlatformEngines #Note: supplies unpack.

using SHA

export bind_download!, bind_packed_download!, bind_processed!, initialise_artifact, setup


function file_hash(path)
    return open(path) do f
        bytes2hex(sha2_256(f))
    end
end

function record_download!(artifacts_toml, artifact_name, url, tarball_hash)

    dict_artifact = Pkg.Artifacts.parse_toml(artifacts_toml)

    # Obtain artifact's metadata.
    meta = dict_artifact[artifact_name]::Dict{String,Any}

    # Add download information.
    meta["url"] = url
    meta["sha256"] = tarball_hash #Note: doesn't seem necessary as the artifact has will capture discrepancies -- though it does provide the opportunity to leave suff in a temp directory and stop propagation.

    # Overwrite artifact's metadata.
    dict_artifact[artifact_name] = meta

    # Spit it out onto disk.
    open(artifacts_toml, "w") do io
        Pkg.TOML.print(io, dict_artifact, sorted = true)
    end
end

# function acquire_file(url::AbstractString, hash::AbstractString)
#     tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for
#         Pkg.PlatformEngines.download_verify(url, hash, joinpath(path_artifact, basename(url))
#     end
#
#     return tree_hash
# end

function acquire_file(url::AbstractString, check::Union{Nothing, AbstractString} = nothing; verbose::Bool = false)

    function acquire(path::AbstractString, io::IO)

        Pkg.PlatformEngines.probe_platform_engines!()
        Pkg.PlatformEngines.download(url, path, verbose = verbose) #Note: this indirection is used to easily obtain and return the tarball_hash.

        tarball_hash = file_hash(path)

        if !isnothing(check) && tarball_hash != check
            error("Unexpected download.")
        end

        # if !isnothing(check) && !verify(path, hash, verbose = verbose)
        #     error("Verification of download failed.")
        # end

        tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.
            cp(path, joinpath(path_artifact, basename(url))) #Note: path is expected for cleanup.
        end

        return tree_hash, tarball_hash
    end

    return mktemp(acquire)
end

function bind_download!(artifacts_toml::String, url::String, artifact_name::String = basename(url); force::Bool = false, verbose::Bool = false)

    # Acquire artifact.
    (tree_hash, tarball_hash) = acquire_file(url)

    # Bind acquired artifact.
    bind_artifact!(artifacts_toml, artifact_name, tree_hash, force = force, lazy = false, platform = nothing)

    # Additionally record download meta.
    record_download!(artifacts_toml, artifact_name, url, tarball_hash)

    return tree_hash
end

function bind_packed_download!(artifacts_toml::String, url::String, artifact_name::String = basename(url); lazy::Bool = true, force::Bool = false, platform::Union{Pkg.Types.Platform,Nothing} = nothing, verbose::Bool = false)

    function acquire(path::AbstractString, io::IO)

        Pkg.PlatformEngines.download(url, path, verbose = verbose)

        tarball_hash = file_hash(path)

        tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.
            Pkg.PlatformEngines.probe_platform_engines!()
            Pkg.PlatformEngines.unpack(path, path_artifact, verbose = verbose)
        end

        return tree_hash, tarball_hash
    end

    # Acquire artifact.
    (tree_hash, tarball_hash) = mktemp(acquire)

    # Bind acquired artifact.
    bind_artifact!(artifacts_toml, artifact_name, tree_hash, download_info = [(url,tarball_hash)], lazy = lazy, force = force, platform = platform)

    return tree_hash
end

function bind_processed!(artifacts_toml::String, artifact_name::String, process::Function; force::Bool = false)

    tree_hash = create_artifact(process)

    bind_artifact!(artifacts_toml, artifact_name, tree_hash, force = force, lazy = false, platform = nothing)

    return tree_hash
end

function setup_file(artifact_name, artifacts_toml; verbose::Bool = false)

    meta = artifact_meta(artifact_name, artifacts_toml)

    url = meta["url"]
    hash = meta["sha256"]

    (acquired_hash, _) = acquire_file(url, hash, verbose = verbose)

    return acquired_hash
end

function setup(process::Function)
    return (artifacts_toml, artifact_name, verbose = verbose) -> create_artifact(process)
end

function initialise_artifact(artifacts_toml::String, artifact_name::String, setup_func::Function = setup_file; verbose::Bool = false)

    # Allow __init__ function to run when Artifacts.toml file does not exist.
    if !isfile(artifacts_toml)
        return nothing
    end

    #
    tree_hash = artifact_hash(artifact_name, artifacts_toml)

    # Allow __init__ function to run when the artifact entry does not exist in Artifacts.toml.
    if tree_hash == nothing
        return nothing
    end

    # Setup the artifact if it does not exist on disk.
    if !artifact_exists(tree_hash)
        setup_hash = setup_func(artifacts_toml, artifact_name, verbose = verbose)
        setup_hash == tree_hash || error("Hash $setup_hash of setup artifact does not match artifact's record.")
    end

    return tree_hash
end

function initialise_artifact(f::Function, args...; kwargs...)
    tree_hash = initialise_artifact(args...; kwargs...)

    if tree_hash === nothing
        return nothing
    end

    return f(tree_hash)
end

end # module
