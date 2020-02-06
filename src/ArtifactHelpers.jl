module ArtifactHelpers

using Pkg
using Pkg.Artifacts
using Pkg.PlatformEngines #Note: supplies unpack.

using Pkg.BinaryPlatforms

using ZipFile

using SHA

export
    File, GZ, Zip, Processed,
    initialise_artifact, setup

abstract type Entry end
abstract type AutoDownloadableEntry <: Entry end
abstract type CustomEntry <: Entry end
abstract type CustomDownloadableEntry <: CustomEntry end

function _url(url::String)
    return [url]
end

function _url(urls::Vector{String})
    return urls
end

mutable struct GZ <: AutoDownloadableEntry
    artifact_name::String
    meta::Dict{String,Any}
    urls::Vector{String}
    platform::Union{Platform,Nothing}
    lazy::Bool
    new_download_info::Vector{Tuple}

    GZ(url; platform = nothing, lazy = true) = new(basename(first(_url(url))), Dict(), _url(url), platform, lazy, Vector{Tuple}())
    GZ(artifact_name, url; platform = nothing, lazy = true) = new(artifact_name, Dict(), _url(url), platform, lazy, Vector{Tuple}())
    GZ(artifact_name, dict::Dict; platform = nothing, lazy = true) = new(artifact_name, dict, Vector{String}(), platform, lazy, Vector{Tuple}())
end

mutable struct File <: CustomDownloadableEntry
    artifact_name::String
    meta::Dict{String,Any}
    platform::Union{Platform,Nothing}

    File(url; platform = nothing) = new(basename(url), Dict("url"=>url), platform)
    File(artifact_name, url; platform = nothing) = new(artifact_name, Dict("url"=>url), platform)
    File(artifact_name, dict::Dict; platform = nothing) = new(artifact_name, dict, platform)
end

mutable struct Zip <: CustomDownloadableEntry
    artifact_name::String
    meta::Dict{String,Any}
    platform::Union{Platform,Nothing}

    Zip(url; platform = nothing) = new(basename(url), Dict("url"=>url), platform)
    Zip(artifact_name, url; platform = nothing) = new(artifact_name, Dict("url"=>url), platform)
    Zip(artifact_name, dict::Dict; platform = nothing) = new(artifact_name, dict, platform)
end

mutable struct Processed <: CustomEntry
    artifact_name::String
    meta::Dict{String,Any}
    platform::Union{Platform,Nothing}

    Processed(artifact_name; platform = nothing) = new(artifact_name, Dict(), platform)
    Processed(artifact_name, dict::Dict; platform = nothing) = new(artifact_name, dict, platform)
end

function name(entry::Entry)
    return entry.artifact_name
end

function metadata(entry::Entry)
    return entry.meta
end

function has(entry::Entry, key)
    return haskey(metadata(entry), key)
end

function Base.get(entry::Entry, key)
    return metadata(entry)[key] #Note: we want an error if the key does not exist.
end

function Base.setindex!(entry::Entry, value, key...)
    return setindex!(metadata(entry), value, key...)
end

function autodownloadable(entry::Entry)
    return has(entry, "download")
end

function verifiable(entry::Entry)

    if autodownloadable(entry)
        return true #Note: we assume the download section has the sha256.
    end

    return has(entry, "sha256")
end


function record!(artifacts_toml::AbstractString, entry::CustomEntry)

    isfile(artifacts_toml) || error("Artifacts.toml does not exist at specified path:", artifacts_toml)

    # Load toml.
    dict_artifact = Pkg.Artifacts.parse_toml(artifacts_toml)

    # Obtain artifact's metadata.
    meta = get(dict_artifact, name(entry), Dict())::Dict{String,Any}

    # Merge with whatever is on file.
    meta = merge(meta, metadata(entry)) #TODO: what does this do with Dicts of Dicts?

    # Overwrite artifact's metadata.
    dict_artifact[name(entry)] = meta

    # Spit it out onto disk.
    open(artifacts_toml, "w") do io
        Pkg.TOML.print(io, dict_artifact, sorted = true)
    end

    return nothing
end

function record!(artifacts_toml::AbstractString, entry::Entry)
    return nothing
end


function acquire!(entry::AutoDownloadableEntry, dest::AbstractString = pwd(); force::Bool = false, verbose::Bool = false)

    Pkg.PlatformEngines.probe_platform_engines!()

    downloaded = false

    if autodownloadable(entry)
        # Bound.

        meta = metadata(entry)

        # Attempt to download from all sources.
        for download_entry in meta["download"]

            url = download_entry["url"]
            tarball_hash = download_entry["sha256"]

            # Pkg.PlatformEngines.download_verify_unpack(url::AbstractString, hash::AbstractString, dest::AbstractString; tarball_path = nothing, ignore_existence::Bool = false, force::Bool = false, verbose::Bool = false)

            # Pkg.PlatformEngines.download_verify(url::AbstractString, hash::AbstractString, dest::AbstractString; verbose::Bool = false, force::Bool = false, quiet_download::Bool = true)

            try

                Pkg.PlatformEngines.download(url, dest, verbose = verbose)

                if Pkg.PlatformEngines.verify(dest, tarball_hash, verbose = verbose)
                    downloaded = true
                    break
                end

            catch e

                if isa(e, InterruptException) || isa(e, MethodError)
                    rethrow(e)
                end
                # If something went wrong during download, continue.
                continue
            end
        end
    else
        # Unboud.

        # Attempt to download from all sources. #TODO: this doesn't make much sense from an artifact creation perspective unless all urls are tested.
        for url in entry.urls
            try
                Pkg.PlatformEngines.download(url, dest, verbose = verbose)

                # Add meta entries.
                push!(entry.new_download_info, (url, file_hash(dest)))

                downloaded = true
                break
            catch e
                if isa(e, InterruptException)
                    rethrow(e)
                end
                # If something went wrong during download, continue.
                continue
            end
        end

    end

    downloaded || error("Nothing downloaded.")

    return entry
end

function acquire!(entry::CustomDownloadableEntry, dest::AbstractString = pwd(); force::Bool = false, verbose::Bool = false)

    Pkg.PlatformEngines.probe_platform_engines!()
    Pkg.PlatformEngines.download(get(entry, "url"), dest, verbose = verbose)

    hash_download = file_hash(dest)

    # if !force && verifiable(entry) && hash_download != get(entry, "sha256")
    #     error("Unexpected download.")
    # end

    if !force && verifiable(entry)
        verbose && @info "Verifying" entry
        Pkg.PlatformEngines.verify(dest, get(entry, "sha256"), verbose = verbose) || error("Unexpected download.")
    end

    setindex!(entry, file_hash(dest), "sha256") #Note: may overwrite existing value with the same value.

    return entry
end

function process(entry::GZ; force::Bool = false, verbose::Bool = false)

    tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.

        mktemp() do dest, io

            acquire!(entry, dest, force = force, verbose = verbose)

            Pkg.PlatformEngines.unpack(dest, path_artifact, verbose = verbose)

        end
    end

    return tree_hash
end

function process(entry::Zip; force::Bool = false, verbose::Bool = false)

    tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.

        mktemp() do dest, io

            acquire!(entry, dest, force = force, verbose = verbose)

            unzip(dest, path_artifact, verbose = verbose)

        end
    end

    return tree_hash
end

function process(entry::File; force::Bool = false, verbose::Bool = false)

    tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.

        mktemp() do dest, io

            acquire!(entry, dest, force = force, verbose = verbose)

            cp(dest, joinpath(path_artifact, name(entry))) #Note: dest is expected for cleanup.

        end
    end

    return tree_hash
end

# function process(func::Function, entry::Entry, args...; kwargs...)
#
#     tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.
#         func(entry, args...; kwargs...)
#     end
#
#     return tree_hash
#
# end

function Pkg.Artifacts.bind_artifact!(artifacts_toml::AbstractString, entry::GZ, process_func::Function = process; force::Bool = false, verbose::Bool = false)

    # bind_artifact!(artifacts_toml::String, name::String, hash::SHA1; platform::Union{Platform,Nothing} = nothing, download_info::Union{Vector{<:Tuple},Nothing} = nothing, lazy::Bool = false, force::Bool = false)

    tree_hash = process_func(entry, force = force, verbose = verbose)

    download_info = entry.new_download_info #TODO: merge with existing download_info?

    # Bind acquired artifact.
    bind_artifact!(artifacts_toml, name(entry), tree_hash, force = force, lazy = entry.lazy, download_info = download_info, platform = entry.platform)

    return nothing

end

function Pkg.Artifacts.bind_artifact!(artifacts_toml::AbstractString, entry::Entry, process_func::Function = process; force::Bool = false, verbose::Bool = false)

    # bind_artifact!(artifacts_toml::String, name::String, hash::SHA1; platform::Union{Platform,Nothing} = nothing, download_info::Union{Vector{<:Tuple},Nothing} = nothing, lazy::Bool = false, force::Bool = false)

    tree_hash = process_func(entry, force = force, verbose = verbose)

    # Bind acquired artifact.
    bind_artifact!(artifacts_toml, name(entry), tree_hash, force = force, lazy = false, platform = entry.platform)

    # Additionally record meta.
    record!(artifacts_toml, entry)

    return nothing

end

function setup(artifact_name, artifacts_toml)

    meta = artifact_meta(artifact_name, artifacts_toml) #TODO: platform.

    if haskey(meta, "download")
        return GZ(artifact_name, meta)
    end

    if haskey(meta, "url") && haszipext(meta["url"])
        return Zip(artifact_name, meta)
    end

    if haskey(meta, "url")
        return File(artifact_name, meta)
    end

    return Processed(artifact_name, meta)

end

function initialise_artifact(artifacts_toml::String, artifact_name::String, process_func::Function = process; verbose::Bool = false)

    # Allow __init__ function to run when Artifacts.toml file does not exist.
    if !isfile(artifacts_toml)
        @warn "Artifacts.toml does not exist at specified path." artifacts_toml
        return nothing
    end

    # Obtain artifact's recorded hash.
    tree_hash = artifact_hash(artifact_name, artifacts_toml)

    # Allow __init__ function to run when the artifact entry does not exist in Artifacts.toml.
    if tree_hash == nothing
        @warn "An artifact entry for \"$artifact_name\" does not exist in Artifacts.toml."
        return nothing
    end

    # Setup the artifact if it does not exist on disk.
    if !artifact_exists(tree_hash)
        # setup_hash = setup_func(artifact_name, artifacts_toml, verbose = verbose)
        setup_hash = process_func(setup(artifact_name, artifacts_toml), force = false, verbose = verbose) #Note: not forcing during initialisation.
        setup_hash == tree_hash || error("Hash $setup_hash of setup artifact does not match the entry for \"$artifact_name\".")
    end

    verbose && @info "Initialised $artifact_name." tree_hash

    return tree_hash
end

function initialise_artifact(f::Function, args...; kwargs...)
    tree_hash = initialise_artifact(args...; kwargs...)

    if tree_hash === nothing
        return nothing
    end

    return f(tree_hash)
end

function file_hash(path)
    return open(path) do file
        bytes2hex(sha2_256(file))
    end
end

function haszipext(path::AbstractString)

    (_, ext) = splitext(path)

    return ext == ".zip"
end

function unzip(src, dest; verbose::Bool = false)

    if !isfile(src)
        error("Source does not exist.")
    end

    if !isdir(dest)
        error("Destination does not exist.")
    end

    verbose && @info "Unzipping." src dest

    r = ZipFile.Reader(src)

    try
        for f in r.files

            verbose && (println("Filename: $(f.name)"))

            if f.method == ZipFile.Store
                mkpath(joinpath(dest, f.name))
            end

            if f.method == ZipFile.Deflate
                path = joinpath(dest, f.name)
                mkpath(dirname(path))
                !isdirpath(f.name) && write(path, read(f))
            end

        end
    finally
        close(r)
    end

    return dest
end

end # module
