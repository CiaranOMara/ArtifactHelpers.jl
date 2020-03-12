# ArtifactHelpers.jl

[![Project Status: Active - The project has reached a stable, usable state and is being actively developed.](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)
[![Run tests Unix/Linux](https://github.com/CiaranOMara/ArtifactHelpers.jl/workflows/Run%20tests%20Unix/Linux/badge.svg)](https://github.com/CiaranOMara/ArtifactHelpers.jl/actions?query=workflow%3A%22Run+tests%20Unix/Linux%22)
[![Run tests Windows](https://github.com/CiaranOMara/ArtifactHelpers.jl/workflows/Run%20tests%20Windows/badge.svg)](https://github.com/CiaranOMara/ArtifactHelpers.jl/actions?query=workflow%3A%22Run%20tests%20Windows%22)

> This project follows the [semver](http://semver.org) pro forma and uses the [git-flow branching model](http://nvie.com/git-model "original
blog post").

## Overview

The `ArtifactHelpers` package provides a set of helper functions that overlay Julia's Artifact framework to assist with binding, initialisation, and possible recreation of Artifacts.

## Installation
    (v1.1) pkg> add https://github.com/CiaranOMara/ArtifactHelpers.jl

## Usage Example
This example shows a usage pattern for `ArtifactHelpers` within a package/project.
This pattern makes use of Julia's build system.
The build system decouples dependencies required to generate the Artifacts from the package as well as provide a means in which to distribute and _recreate_ Artifacts across systems.

```
# Project layout.
./
├── Artifacts.toml
├── Project.toml
├── README.md
├── deps
│   ├── Project.toml
│   └── build.jl
└── src
    └── <package_name>.jl
```

When a package is first installed, Julia automatically runs the `deps/build.jl` file as part of the package build step.
However, when working on the `deps/build.jl` file, builds can be triggered from the [Julia REPL](https://docs.julialang.org/en/v1/manual/getting-started/) in [pkg mode](https://docs.julialang.org/en/v1/stdlib/Pkg/) with the [build](https://julialang.github.io/Pkg.jl/v1/creating-packages/#Adding-a-build-step-to-the-package-1) command.

Shown below is an example of a `deps/build.jl` file that performs the initial binding of Artifacts to the `Artifacts.toml` file.

```julia
using ArtifactHelpers

artifacts_toml = joinpath(@__DIR__, "Artifacts.toml")

bind_artifact!(artifacts_toml, File("http://somwhere/random.csv"), force = true, verbose = true)
bind_artifact!(artifacts_toml, Zip("http://somwhere/random.zip"), force = true, verbose = true)
bind_artifact!(artifacts_toml, AutoDownloadable("http://somwhere/random.tar.gz"), force = true, verbose = true)

bind_artifact!(artifacts_toml, "Processed", force = true, verbose = true) do path_artifact #Note: this will create an artifact that is ready for use.
    # Do stuff ...
end
```

Once the `Artifacts.toml` file is populated, it should be committed to the git history so that the dual purpose `build_artifact!` method has the information it requires to verify recreated Artifacts.

After the Artifacts are setup they can be accessed with the [`artifact_path()`](https://julialang.github.io/Pkg.jl/v1/api/#Pkg.Artifacts.artifact_path) method or the [@artifact_str](https://julialang.github.io/Pkg.jl/v1/api/#Pkg.Artifacts.@artifact_str) macro.
Below is an example of populating the globals of `./src/<package_name>.jl` with Artifact items.
```julia
module <package_name>

using Pkg.Artifacts

path_random_tar_gz = ""
random_csv = ""
path_random_zip = ""
path_processed = ""

function __init__()

    global path_random_tar_gz = abspath(artifact"random.tar.gz")

    global random_csv = joinpath(abspath(artifact"random.csv"), "random.csv")

    global path_random_zip = abspath(artifact"random.zip")

    global path_processed = abspath(artifact"processed")

end

# module code ...

end # module

```

## Contributions
> This package is still very much a work in progress.
I haven't settled on a pattern and am very much open to suggestions and improvements.

## Acknowledgements
- [Original blog post](https://julialang.org/blog/2019/11/artifacts/) by Elliot Saba, Stefan Karpinski, Kristoffer Carlsson
- [The latest docs of Pkg.jl](https://julialang.github.io/Pkg.jl/dev/artifacts/)
