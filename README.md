# ArtifactHelpers.jl

This package contains a set of helper functions that overlay Julia's Artifact framework to assist with binding, initialisation, and possible recreation of Artifacts.

> This package is still very much a work in progress.
I haven't settled on a pattern and am very much open to suggestions and improvements.

## Installation
    (v1.1) pkg> add https://github.com/CiaranOMara/ArtifactHelpers.jl

## Usage Example
I have found that there are two stages of Artifact creation outside of the BinaryWrapper paradigm: the initial binding and then the _recreation_ and use across systems.


This example shows a usage pattern of `ArtifactHelpers` within a project.
```
# Project layout.
./
├── Artifacts.toml
├── Project.toml
├── README.md
├── generate_artifacts.jl
└── src
    └── <package_name>.jl
```

The contents of the `./generate_artifacts.jl` file performs the initial binding of Artifacts to the `Artifacts.toml` file, which is committed to the git history once populated.
An example of the initial binding with `ArtifactHelpers` is shown below.
```julia
using Pkg
Pkg.activate(@__DIR__)
Pkg.update()

using ArtifactHelpers

artifacts_toml = touch(joinpath(@__DIR__, "Artifacts.toml"))

bind_artifact!(artifacts_toml, File("http://somwhere/random.csv"), force = true, verbose = true)
bind_artifact!(artifacts_toml, Zip("http://somwhere/random.zip"), force = true, verbose = true)
bind_artifact!(artifacts_toml, AutoDownloadable("http://somwhere/random.tar.gz"), force = true, verbose = true)

using <package_name>
bind_artifact!(artifacts_toml, Processed("Processed"), <package_name>.process, force = true, verbose = true)
```

Once the `Artifacts.toml` file is populated, `ArtifactHelpers` may be used to initialise and possibly recreate Artifacts within modules or scripts.
Below is an example of Artifact initialisation within `./src/<package_name>.jl`.
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

    initialise_artifact(artifacts_toml, "processed", process, verbose = true) do tree_hash
        global path_processed = abspath(artifact_path(tree_hash))
    end

end

function process(entry::Processed; force::Bool = false, verbose::Bool = false)

    tree_hash = create_artifact() do path_artifact #Note: this will create an artifact that is ready for use.
        # Do stuff.
    end

    return tree_hash
end

# module code ...

end # module

```
