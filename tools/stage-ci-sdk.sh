#!/usr/bin/env bash
# Stage an unreleased XenServer SDK, built by xen-api's own CI or locally, for building and running the
# workflow examples against it.
#
# xen-api's "Build and test (other)" workflow builds every SDK binding on each push. This fetches the
# bindings from the latest completed run on a branch (of xapi-project/xen-api or a fork of it), or takes
# them from a local build by tools/build-sdk/build-sdk.sh, and stages them where the examples look for them:
#
#   go/goSDK/                    Go binding source (the directory the Go examples' go.mod points at)
#   .ci-sdk/python/XenAPI/       Python binding, from the same commit
#   .ci-sdk/java/                Java binding jar
#   .ci-sdk/nuget/               XenServer.NET package
#   .ci-sdk/powershell/          XenServerPSModule for PowerShell 7
#   .ci-sdk/env.sh               variables for using the above; source it
#
# Usage:
#   tools/stage-ci-sdk.sh [-R owner/xen-api] [-b branch] [--run id]
#   tools/stage-ci-sdk.sh --from <directory>     (run for you by build-sdk.sh)
#   source .ci-sdk/env.sh
#
# Defaults to xapi-project/xen-api master. Fetching needs the GitHub CLI (gh), logged in.
set -euo pipefail

usage="usage: $0 [-R owner/xen-api] [-b branch] [--run id] | --from <directory>"
repo=xapi-project/xen-api
branch=master
run=
from=
while [ $# -gt 0 ]; do
    case "$1" in
        -R) repo=$2; shift 2 ;;
        -b) branch=$2; shift 2 ;;
        --run) run=$2; shift 2 ;;
        --from) from=$(cd "$2" && pwd); shift 2 ;;
        *) echo "$usage" >&2; exit 2 ;;
    esac
done

root=$(cd "$(dirname "$0")/.." && pwd)
stage=$root/.ci-sdk
artifacts="SDK_Artifacts_Go SDK_Artifacts_Java SDK_Binaries_CSharp SDK_Binaries_XenServerPowerShell_NET10"

rm -rf "$stage"
mkdir -p "$stage/python" "$stage/java" "$stage/nuget" "$stage/powershell"

if [ -n "$from" ]; then
    # A local build, already laid out like the CI artifacts, with the Python binding beside them.
    built=$from
    origin="the local build of $(cat "$from/BUILT-FROM" 2>/dev/null || echo "an unknown checkout")"
else
    if [ -z "$run" ]; then
        # The newest completed run, whatever its conclusion: a failing test elsewhere in the workflow does
        # not stop the SDKs being built, and the artifact check below catches a run that didn't get that far.
        run=$(gh run list -R "$repo" -b "$branch" -w "Build and test (other)" -s completed -L 1 \
            --json databaseId -q '.[0].databaseId')
        [ -n "$run" ] || { echo "no completed 'Build and test (other)' run on $repo $branch" >&2; exit 1; }
    fi
    sha=$(gh run view "$run" -R "$repo" --json headSha -q .headSha)
    have=$(gh api "repos/$repo/actions/runs/$run/artifacts?per_page=100" \
        -q '[.artifacts[] | select(.expired | not) | .name] | join(" ")')
    for a in $artifacts; do
        case " $have " in *" $a "*) ;; *) echo "run $run has no $a artifact (expired, or the SDK build failed)" >&2; exit 1 ;; esac
    done
    origin="$repo run $run ($branch @ $sha)"
    built=$stage/download
    for a in $artifacts; do gh run download "$run" -R "$repo" -n "$a" -D "$built/$a"; done
    # Python: the binding isn't built by the workflow; take it from the commit the run built.
    mkdir -p "$built/python/XenAPI"
    for f in __init__.py XenAPI.py; do
        gh api -H "Accept: application/vnd.github.raw" "repos/$repo/contents/python3/examples/XenAPI/$f?ref=$sha" \
            > "$built/python/XenAPI/$f"
    done
fi
echo "Staging the SDK built by $origin"

# Go: replace the binding the Go examples build against.
rm -rf "$root/go/goSDK"
cp -r "$built/SDK_Artifacts_Go/src" "$root/go/goSDK"
cp -r "$built/python/XenAPI" "$stage/python/"
cp "$built"/SDK_Artifacts_Java/xen-api-*-prerelease.jar "$stage/java/"
cp "$built"/SDK_Binaries_CSharp/*.nupkg "$stage/nuget/"
cp -r "$built/SDK_Binaries_XenServerPowerShell_NET10" "$stage/powershell/XenServerPSModule"
rm -rf "$stage/download"

jar=$(ls "$stage"/java/xen-api-*-prerelease.jar)
java_version=$(basename "$jar" .jar); java_version=${java_version#xen-api-}
nupkg=$(ls "$stage"/nuget/*.nupkg)
dotnet_version=$(basename "$nupkg" .nupkg); dotnet_version=${dotnet_version#XenServer.NET.}

native() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
sep=:; command -v cygpath >/dev/null && sep=';'
cat > "$stage/env.sh" <<EOF
# The SDK built by $origin.

# Python: python workflows.py ...
export PYTHONPATH="$(native "$stage/python")"

# PowerShell 7: pwsh -File workflows.ps1 ...
export PSModulePath="$(native "$stage/powershell")$sep\${PSModulePath:-}"

# C#: every build of the SDK has the same placeholder version, so restore into a private package folder
# rather than NuGet's global cache, which would keep serving whichever build it saw first.
export CI_SDK_DOTNET_ARGS="-p:XenServerSdkVersion=$dotnet_version -p:RestoreAdditionalProjectSources=$(native "$stage/nuget") -p:RestorePackagesPath=$(native "$stage/nuget-packages")"
#   dotnet build \$CI_SDK_DOTNET_ARGS

# Java: install the jar once per staging, then build with its version.
#   mvn install:install-file -Dfile="$(native "$jar")" -DgroupId=com.xenserver -DartifactId=xen-api -Dversion=$java_version -Dpackaging=jar
#   mvn compile exec:java -Dxenapi.version=$java_version -Dexec.args="..."
export CI_SDK_JAVA_JAR="$(native "$jar")" CI_SDK_JAVA_VERSION=$java_version
EOF
echo "Staged. Now: source .ci-sdk/env.sh"
