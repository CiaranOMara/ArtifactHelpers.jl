module ArtifactHelpers

using Pkg
using Pkg.Artifacts
using Pkg.PlatformEngines #Note: supplies unpack.

using SHA

export bind_download!, bind_processed!, initialise_processed_artifact


function bind_download!(artifacts_toml::String, url::String, artifact_name::String=basename(url); lazy::Bool = true, force::Bool = false, packed::Bool=false, platform::Union{Pkg.Types.Platform,Nothing} = nothing)

    function acquire(path::AbstractString, io::IO)
        download(url, path)

        tarball_hash = open(path) do f
            bytes2hex(sha2_256(f))
        end

        tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.
            if packed === true
                Pkg.PlatformEngines.probe_platform_engines!()
                Pkg.PlatformEngines.unpack(path, path_artifact, verbose=true)
            else
                cp(path, joinpath(path_artifact, basename(url))) #Note: path is expected for cleanup.
            end
        end

        return tree_hash, tarball_hash
    end

    # Acquire artifact.
    (tree_hash, tarball_hash) = mktemp(acquire)

    bind_artifact!(artifacts_toml, artifact_name, tree_hash, download_info=[(url,tarball_hash)], lazy=lazy, force=force, platform=platform)

    return tree_hash

end

function bind_processed!(artifacts_toml::String, artifact_name::String, process::Function, check_process_dependencies::Function = ()->(true); force::Bool = false, platform::Union{Pkg.Types.Platform,Nothing} = nothing)

    check_process_dependencies()

    # create_artifact() returns the content-hash of the artifact directory once we're finished creating it.
    tree_hash = create_artifact(process)

    #=
    Now bind that hash within our `Artifacts.toml`.
    `force = true` means that if it already exists, just overwrite with the new content-hash.
    Unless the source files change, we do not expect the content hash to change, so this should not cause unnecessary version control churn.
    =#
    bind_artifact!(artifacts_toml, artifact_name, tree_hash, lazy = false, force = force, platform=platform)

    return tree_hash

end

function initialise_processed_artifact(artifacts_toml::String, artifact_name::String, process::Function, check_process_dependencies::Function = ()->(true))

    # Allow __init__ function to run when Artifacts.toml file does not exist.
    if !isfile(artifacts_toml)
        return nothing
    end

    #
    tree_hash = artifact_hash(artifact_name, artifacts_toml)

    # Allow __init__ function to run when artifact not exist in Artifacts.toml.
    if tree_hash == nothing
        return nothing
    end

    # Setup the artifact if it does not exist on disk.
    if !artifact_exists(tree_hash)
        setup_hash = bind_processed!(artifacts_toml, artifact_name, process, check_process_dependencies)
        setup_hash == tree_hash || error("Hash of setup artifact does not match.")
    end

    return tree_hash
end

function initialise_processed_artifact(f::Function, args...)
    tree_hash = initialise_processed_artifact(args...)

    if tree_hash === nothing
        return nothing
    end

    return f(tree_hash)
end

end # module
