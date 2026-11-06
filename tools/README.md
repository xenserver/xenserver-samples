# Tools

- [Running against an unreleased SDK](#running-against-an-unreleased-sdk)
- [Generating the workflow docs](#generating-the-workflow-docs)

## Running against an unreleased SDK

Running the workflow examples against an SDK that hasn't been released yet, so a change to the SDK can be
checked against all of them before it ships.

### From xen-api's CI

xen-api's CI builds every SDK on each push. Fetch the build from the latest run on a branch, then use it:

```
tools/stage-ci-sdk.sh                                    # xapi-project/xen-api master
tools/stage-ci-sdk.sh -R <owner>/xen-api -b <branch>     # a branch on a fork
source .ci-sdk/env.sh
```

### Built locally

Builds the SDK from a xen-api checkout in Docker, the way xen-api's CI does, uncommitted changes included,
and stages it the same way:

```
tools/build-sdk/build-sdk.sh <xen-api checkout>
source .ci-sdk/env.sh
```

The first run builds the OCaml build environment image, which takes a few minutes; it is reused until the
checkout's `opam/` files change.

### Using the staged SDK

The Go examples build against it straight away: it replaces `go/goSDK`. For the others, `.ci-sdk/env.sh`
sets the paths, and says how to point each build at it:

| Language | |
|---|---|
| PowerShell 7 | `PSModulePath` |
| Python | `PYTHONPATH` |
| C# | `dotnet build $CI_SDK_DOTNET_ARGS` |
| Java | install `$CI_SDK_JAVA_JAR` with `mvn install:install-file`, then `-Dxenapi.version=$CI_SDK_JAVA_VERSION` |

Both scripts are bash; on Windows, run them from Git Bash.

## Generating the workflow docs

The pages in [`docs/workflows/`](../docs/workflows/README.md) are generated: each shows a workflow's
description from `workflows.json`, its code in every language (cut from the sources, so it cannot drift
from them) and example output from running it. After changing a workflow, or adding one, regenerate them
and commit the result with your change:

```
python3 tools/docs/generate_docs.py
```

`--check` changes nothing: it fails if a page is out of date, or if `workflows.json` and the sources
disagree (a listed workflow some language doesn't implement, or one a source implements that isn't
listed). Every workflow file prints `OK: <workflow>` when it succeeds; that line is how the generator
knows which workflow a file belongs to.

The example output is kept in `tools/docs/sample-output.tsv`, one line per language and workflow. To
record new output, pass the run's output with `--captured <file>` (lines of
`<language><TAB><workflow><TAB><output>`, with newlines written as `
`). Output is replaced only when
the code that produced it has changed, so a rerun doesn't rewrite pages for nothing; `--refresh` takes
it all. Needs Python 3 and nothing else.
