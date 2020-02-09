module ArtifactHelpers

using Pkg
using Pkg.Artifacts
using Pkg.PlatformEngines #Note: supplies unpack.

using Pkg.BinaryPlatforms

using ZipFile

using SHA

import Base: SHA1

export
    File, AutoDownloadable, Zip, Processed,
    build_artifact!, initialise_artifact, setup

const AUTODOWNLOADABLES = [".gz"]

TYPES = []

function __init__()
    global TYPES = [(autodownloadable, AutoDownloadableEntry), (iszip, Zip), (downloadable, File), (islocal, Processed) ] #Note: order is relevant.
end

abstract type Entry end
abstract type DownloadableEntry <: Entry end
abstract type CustomEntry <: Entry end

function _url(url::String)
    return [url]
end

function _url(urls::Vector{String})
    return urls
end

mutable struct AutoDownloadableEntry <: DownloadableEntry
    artifact_name::String
    meta::Dict{String,Any}
    urls::Vector{String}
    platform::Union{Platform,Nothing}
    lazy::Bool
    new_download_info::Vector{Tuple}

    AutoDownloadableEntry(url; platform = nothing, lazy = true) = new(basename(first(_url(url))), Dict(), _url(url), platform, lazy, Vector{Tuple}())
    AutoDownloadableEntry(artifact_name, url; platform = nothing, lazy = true) = new(artifact_name, Dict(), _url(url), platform, lazy, Vector{Tuple}())
    AutoDownloadableEntry(artifact_name, dict::Dict; platform = nothing, lazy = true) = new(artifact_name, dict, Vector{String}(), platform, lazy, Vector{Tuple}())
end

const AutoDownloadable = AutoDownloadableEntry

mutable struct File <: DownloadableEntry
    artifact_name::String
    meta::Dict{String,Any}
    platform::Union{Platform,Nothing}

    File(url; platform = nothing) = new(basename(url), Dict("url"=>url), platform)
    File(artifact_name, url; platform = nothing) = new(artifact_name, Dict("url"=>url), platform)
    File(artifact_name, dict::Dict; platform = nothing) = new(artifact_name, dict, platform)
end

mutable struct Zip <: DownloadableEntry
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

function Base.haskey(entry::E, key) where E <: Entry
    return haskey(metadata(entry), key)
end

function Base.get(entry::Entry, key)
    return metadata(entry)[key] #Note: default is not provided, we want an error if the key does not exist.
end

function Base.setindex!(entry::Entry, value, key...)
    return setindex!(metadata(entry), value, key...)
end

function hassha256(entry::E) where E <: Entry

    #Note: the sha256 will be in the meta.

    if haskey(entry, "sha256")
        return true
    end

    if haskey(entry, "download")
        for download_entry in get(entry, "download")

            if isa(download_entry, Dict) && haskey(download_entry, "sha256")
                return true
            end

            @error "Unaccounted download_entry" typeof(download_entry) download_entry #TODO: Handle Array of Dicts?

        end
    end

    return false

end

function record_sha256!(entry::DownloadableEntry, url, str_hash) #TODO: make consistent with possibility for vector of urls.

    setindex!(entry, str_hash, "sha256")

    return entry
end

function record_sha256!(entry::AutoDownloadableEntry, url, str_hash)
    push!(entry.new_download_info, (url, str_hash))

    return entry
end

function isurl(str::String)
    check = "http"
    len = length(check)
    return length(str) >= len && str[1:len] == check
end

function iszip(path::AbstractString)

    (_, ext) = splitext(path)

    return isurl(path) && ext == ".zip"
end

function iszip(meta::Dict)
    return haskey(meta, "url") && iszip(meta["url"])
end

function autodownloadable(entry::String)
    (_, ext) = splitext(entry)

    return isurl(entry) && in(ext, AUTODOWNLOADABLES)
end

function autodownloadable(meta::Dict)
    return haskey(meta, "download") #TODO: subject to change as custom types converge.
end

function downloadable(entry::String)
    return isurl(entry) #TODO: find and use official url checker.
end

function downloadable(meta::Dict)
    return haskey(meta, "url") #Note: needs to be called after autodownloadable and zip!
end

function islocal(entry::String)
    return !isurl(entry) #TODO: find and use official url checker.
end

function islocal(meta::Dict)
    return !haskey(meta, "url") #Note: needs to be called after autodownloadable and zip!
end

struct Verifiable{x} end
Verifiable(x::Bool) = Verifiable{x}()

function isverifiable(entry::Entry)
    return hassha256(entry)
end

function isverifiable(url::String)
    return false
end

function _download(url::AbstractString, dest::AbstractString; verbose::Bool = false)
    Pkg.PlatformEngines.probe_platform_engines!()
    return Pkg.PlatformEngines.download(url, dest, verbose = verbose) #Note: throws an error if unsuccessfull, otherwise returns path.
end

function _download(url::AbstractString, dest::AbstractString, tarball_hash; verbose::Bool = false)
    Pkg.PlatformEngines.probe_platform_engines!()
    downloaded = Pkg.PlatformEngines.download(url, dest, verbose = verbose) #Note: throws an error if unsuccessfull, otherwise returns path.

    result = Pkg.PlatformEngines.verify(dest, tarball_hash, verbose = verbose)

    result || error("Unexpected download.")

    return downloaded
end

function _download(entry::Entry, dest::AbstractString; kwargs...)
    return _download(entry, dest, Verifiable(isverifiable(entry)); kwargs...)
end

function _download(entry::AutoDownloadableEntry, dest::AbstractString, ::Verifiable{false}; kwargs...) #

    meta = metadata(entry)

    # Attempt to download from all sources.
    for url in entry.urls
        try

            downloaded = _download(url, dest; kwargs...) #Note: throws erro if unsuccessfull.
            record_sha256!(entry, url, file_hash(dest))
            return downloaded

        catch e

            if isa(e, InterruptException) || isa(e, MethodError) || isa(e, UndefVarError)
                rethrow(e)
            end
            # If something went wrong during download, continue.
            continue
        end

    end

    error("Nothing downloaded.")

end

function _download(entry::AutoDownloadableEntry, dest::AbstractString, ::Verifiable{true}; kwargs...)

    meta = metadata(entry)

    # Attempt to download from all sources.
    for download_entry in meta["download"]

        url = download_entry["url"]
        tarball_hash = download_entry["sha256"]

        try
            downloaded = _download(url, dest, tarball_hash; kwargs...) #Note: throws erro if unsuccessfull.
            return downloaded
        catch e

            if isa(e, InterruptException) || isa(e, MethodError) || isa(e, UndefVarError)
                rethrow(e)
            end
            # If something went wrong during download, continue.
            continue
        end
    end

    error("Nothing downloaded.")

end

function _download(entry::DownloadableEntry, dest::AbstractString, ::Verifiable{false}; kwargs...)
    url = get(entry, "url") #TODO: vector of URLs.
    downloaded = _download(url, dest; kwargs...)
    record_sha256!(entry, url, file_hash(dest))
    return downloaded
end

function _download(entry::DownloadableEntry, dest::AbstractString, ::Verifiable{true}; kwargs...)
    return _download(get(entry, "url"), dest, get(entry, "sha256"); kwargs...)
end

function unpack(entry::AutoDownloadableEntry, src::AbstractString, dest::AbstractString; verbose::Bool = false)
    return Pkg.PlatformEngines.unpack(src, dest, verbose = verbose)
end

function unpack(entry::Zip, src::AbstractString, dest::AbstractString; verbose::Bool = false)
    return unzip(src, dest, verbose = verbose)
end

function unpack(entry::File, src::AbstractString, dest::AbstractString; verbose::Bool = false)
    verbose && @info "Copying." src dest
    return cp(src, joinpath(dest, name(entry))) #Note: src is expected for cleanup.
end

function unpack(entry::Entry, src::AbstractString, dest::AbstractString; verbose::Bool = false)
    verbose && @info "Nothing to unpack."
    return
end

function setup(str::String)

    for (test, type) in TYPES
        if test(str)
            return type(str)
        end
    end

    error("Unknown entry type.")

end

function setup(artifact_name, artifacts_toml)

    meta = artifact_meta(artifact_name, artifacts_toml) #TODO: platform.

    for (test, type) in TYPES
        if test(meta)
            return type(artifact_name, meta)
        end
    end

    error("Unknown entry type.")

end

function record!(artifacts_toml::AbstractString, entry::Entry) #TODO: type Entry actually captures custom toml entries.

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

function record!(artifacts_toml::AbstractString, entry::AutoDownloadableEntry)
    return nothing
end

function process(entry::DownloadableEntry; force::Bool = false, verbose::Bool = false)

    tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.

        mktemp() do file_tmp, io

            _download(entry, file_tmp, verbose = verbose)

            unpack(entry, file_tmp, path_artifact, verbose = verbose)

        end
    end

    return tree_hash
end

function build_artifact!(artifacts_toml::String, entry::Entry, process_func::Function = process; force::Bool = false, verbose::Bool = false)

    if !isfile(artifacts_toml)
        error("Artifacts.toml does not exist at specified path: ", artifacts_toml)
    end

    artifact_name = name(entry)

    # Obtain artifact's recorded hash.
    tree_hash = artifact_hash(artifact_name, artifacts_toml)

    if tree_hash == nothing
        @warn "Building and binding a new artifact." artifact_name
        tree_hash = process_func(entry, force = force, verbose = verbose)

        bind_artifact!(artifacts_toml, entry, tree_hash; force = force, verbose = verbose)

        @info "Built $artifact_name." tree_hash

    end

    # Setup the artifact if it does not exist on disk.
    if !artifact_exists(tree_hash)
        @warn "Rebuilding artifact." artifact_name

        # setup_hash = setup_func(artifact_name, artifacts_toml, verbose = verbose)
        setup_hash = process_func(entry, force = force, verbose = verbose) #Note: not forcing during initialisation.
        setup_hash == tree_hash || error("Hash $setup_hash of setup artifact does not match the entry for \"$artifact_name\".")

        @info "Rebuilt $artifact_name." tree_hash

    end

    @info "Skipped build of $artifact_name." tree_hash

    return tree_hash

end

function build_artifact!(artifacts_toml::String, str::String, process_func::Function = process; kwargs...)
    return build_artifact!(artifacts_toml, setup(str), process_func; kwargs...)
end

function build_artifact!(kernel::Function, artifacts_toml::String, entry; kwargs...)

    function wrapped_kernel(entry::Entry; kwargs...) #Note: kwargs captures and diffuses.

        tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.
            kernel(path_artifact)
        end

        return tree_hash
    end

    return build_artifact!(artifacts_toml, entry, wrapped_kernel; kwargs...)
end

function Pkg.Artifacts.bind_artifact!(artifacts_toml::AbstractString, entry::AutoDownloadableEntry, tree_hash::SHA1; force::Bool = false, verbose::Bool = false)

    # bind_artifact!(artifacts_toml::String, name::String, hash::SHA1; platform::Union{Platform,Nothing} = nothing, download_info::Union{Vector{<:Tuple},Nothing} = nothing, lazy::Bool = false, force::Bool = false)

    download_info = entry.new_download_info #TODO: merge with existing download_info?

    # Bind acquired artifact.
    bind_artifact!(artifacts_toml, name(entry), tree_hash, force = force, lazy = entry.lazy, download_info = download_info, platform = entry.platform)

    return nothing

end

function Pkg.Artifacts.bind_artifact!(artifacts_toml::AbstractString, entry::Entry, tree_hash::SHA1; force::Bool = false, verbose::Bool = false)

    # bind_artifact!(artifacts_toml::String, name::String, hash::SHA1; platform::Union{Platform,Nothing} = nothing, download_info::Union{Vector{<:Tuple},Nothing} = nothing, lazy::Bool = false, force::Bool = false)

    # Bind acquired artifact.
    bind_artifact!(artifacts_toml, name(entry), tree_hash, force = force, lazy = false, platform = entry.platform)

    # Additionally record meta.
    record!(artifacts_toml, entry)

    return nothing

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
