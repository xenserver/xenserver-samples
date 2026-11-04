# Tools

Running the workflow examples against an SDK that hasn't been released yet, so a change to the SDK can be
checked against all of them before it ships.

## From xen-api's CI

xen-api's CI builds every SDK on each push. Fetch the build from the latest run on a branch, then use it:

```
tools/stage-ci-sdk.sh                                    # xapi-project/xen-api master
tools/stage-ci-sdk.sh -R <owner>/xen-api -b <branch>     # a branch on a fork
source .ci-sdk/env.sh
```

## Built locally

Builds the SDK from a xen-api checkout in Docker, the way xen-api's CI does, uncommitted changes included,
and stages it the same way:

```
tools/build-sdk/build-sdk.sh <xen-api checkout>
source .ci-sdk/env.sh
```

The first run builds the OCaml build environment image, which takes a few minutes; it is reused until the
checkout's `opam/` files change.

## Using the staged SDK

The Go examples build against it straight away: it replaces `go/goSDK`. For the others, `.ci-sdk/env.sh`
sets the paths, and says how to point each build at it:

| Language | |
|---|---|
| Python | `PYTHONPATH` |
| PowerShell 7 | `PSModulePath` |
| C# | `dotnet build $CI_SDK_DOTNET_ARGS` |
| Java | install `$CI_SDK_JAVA_JAR` with `mvn install:install-file`, then `-Dxenapi.version=$CI_SDK_JAVA_VERSION` |

Both scripts are bash; on Windows, run them from Git Bash.
