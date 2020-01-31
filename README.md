# ArtifactHelpers.jl

> This package is still very much a work in progress. I haven't settled on a pattern and am very much open to suggestions and improvements.

This package contains a set of helper functions that overlay Julia's Artifact framework to assist with binding and initialisation of Artifacts.

I have found that there are two stages of Artifact creation: the initial binding and then the repeatable use across systems.

## Usage Example

```
# Project layout.
./
├── Artifacts.toml
├── LICENSE
├── Manifest.toml
├── Project.toml
├── README.md
├── generate_artifacts.jl
└── src
    └── <package_name>.jl
```

Initial binding of Artifacts carried out in `./generate_artifacts.jl`.
```julia
using Pkg
Pkg.activate(@__DIR__)
Pkg.update()

using ArtifactHelpers

artifacts_toml = touch(joinpath(@__DIR__, "Artifacts.toml"))

bind_packed_download!(artifacts_toml, "http://somwhere/random.tar.gz", force = true, verbose = true)
bind_download!(artifacts_toml, "http://somwhere/random.csv", force = true, verbose = true)
bind_download!(artifacts_toml, "http://somwhere/random.zip", force = true, verbose = true)

using <package_name>
bind_processed!(artifacts_toml, "processed", <package_name>.process, force=true)
```

The recreation/reuse of Artifacts in `./src/<package_name>.jl` (main package entry).
```julia
module <package_name>

using Pkg.Artifacts
using ArtifactHelpers

path_random_tar_gz = ""
path_random_csv = ""
path_random_zip = ""
path_processed = ""

function __init__()

    artifacts_toml = joinpath(@__DIR__, "..", "Artifacts.toml")

    initialise_artifact(artifacts_toml, "random.tar.gz", verbose = true) do tree_hash
        global path_random_tar_gz = abspath(artifact_path(tree_hash)
    end

    initialise_artifact(artifacts_toml, "random.csv", verbose = true) do tree_hash
        global path_random_csv = joinpath(abspath(artifact_path(tree_hash)), "random.csv")
    end

    initialise_artifact(artifacts_toml, "random.zip", verbose = true) do tree_hash
        global path_random_zip = abspath(artifact_path(tree_hash)
    end

    initialise_artifact(artifacts_toml, "processed", setup(process), verbose = true) do tree_hash
        global path_processed = abspath(artifact_path(tree_hash))
    end

end

function process(path_artifact::String)
    # Do stuff.
end

end # module

```
