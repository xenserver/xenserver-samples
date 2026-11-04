#!/usr/bin/env bash
# Build the XenServer SDK from a xen-api checkout, in Docker, the way xen-api's CI builds it
# (.github/workflows/generate-and-build-sdks.yml), and stage it for the examples.
#
# The checkout's working tree is built as it stands, uncommitted changes included, so an SDK fix can be
# tried against the examples before it is committed. The output goes to .sdk-build/, laid out like the CI
# run's artifacts, and is then staged by tools/stage-ci-sdk.sh --from.
#
# Usage:
#   tools/build-sdk/build-sdk.sh <xen-api checkout> [--version 1912.6.23]
#   source .ci-sdk/env.sh
#
# Needs Docker. The first run builds the OCaml environment image, which takes a while; it is reused until
# the checkout's opam/ files change.
set -euo pipefail

src=
version=1912.6.23   # the placeholder the CI builds with
while [ $# -gt 0 ]; do
    case "$1" in
        --version) version=$2; shift 2 ;;
        -*) echo "usage: $0 <xen-api checkout> [--version x.y.z]" >&2; exit 2 ;;
        *) src=$(cd "$1" && pwd); shift ;;
    esac
done
[ -n "$src" ] && [ -f "$src/ocaml/sdk-gen/dune" ] || { echo "usage: $0 <xen-api checkout> [--version x.y.z]" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=$root/.sdk-build
native() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
# Git Bash would otherwise rewrite the container-side paths given to docker run into Windows ones.
docker_run() { MSYS_NO_PATHCONV=1 docker run "$@"; }

# 1. The OCaml environment, tagged by what it is built from.
tag=xenapi-sdk-env:$(cat "$src"/opam/*.opam "$here/Dockerfile" | sha256sum | cut -c1-12)
if ! docker image inspect "$tag" >/dev/null 2>&1; then
    ctx=$(mktemp -d)
    cp -r "$src/opam" "$here/Dockerfile" "$ctx/"
    echo "Building the SDK build environment $tag (slow the first time)"
    docker build -t "$tag" "$ctx"
    rm -rf "$ctx"
fi

rm -rf "$out"
mkdir -p "$out"
head=$(git -C "$src" rev-parse HEAD)
dirty=$(git -C "$src" status --porcelain --untracked-files=no | grep -q . && echo "+uncommitted" || true)
echo "Building the SDK from $src (${head:0:9}$dirty) as $version"

# 2. Generate the SDKs, and build the Java one. The checkout goes in as a tar of its tracked and untracked
#    files, leaving out ignored ones such as _build, and editors' state folders.
(cd "$src" && git ls-files -z -co --exclude-standard | grep -zv -E '^\.(vs|vscode|idea)/' | tar --null -T - -cf -) |
docker_run -i --rm -v "$(native "$out"):/out" \
    -v xenapi-sdk-dune:/home/opam/.cache/dune -v xenapi-sdk-m2:/home/opam/.m2 \
    -e VERSION="$version" "$tag" bash -euc '
    sudo chown opam /home/opam/.cache/dune /home/opam/.m2
    mkdir ~/src && cd ~/src && tar -xf -
    opam exec -- ./configure --xapi_version="v$VERSION"
    opam exec -- make sdk
    share=_build/install/default/share
    mkdir -p /out/SDK_Artifacts_Go /out/SDK_Artifacts_Java /out/source
    cp -rL $share/go/. /out/SDK_Artifacts_Go/ && rm -f /out/SDK_Artifacts_Go/dune
    cp -rL $share/csharp /out/source/csharp
    cp -rL $share/powershell /out/source/powershell
    cd $share/java
    sed -i "s/@SDK_VERSION@/$VERSION-prerelease/" xen-api/src/main/java/com/xensource/xenapi/JsonRpcClient.java
    mvn -f xen-api/pom.xml -B -q -Drevision="$VERSION-prerelease" clean package
    cp xen-api/target/xen-api-*.jar /out/SDK_Artifacts_Java/
'

# 3. The C# SDK and the PowerShell 7 module, as the CI's Windows jobs build them.
docker_run --rm -v "$(native "$out"):/out" -v xenapi-sdk-nuget:/root/.nuget/packages \
    -e VERSION="$version" mcr.microsoft.com/dotnet/sdk:10.0 bash -euc '
    pkg="$VERSION-prerelease-unsigned"
    cp -r /out/source /build
    cd /build/csharp
    sed -i "s/@SDK_VERSION@/$pkg/" src/Session.cs
    dotnet build src/XenServer.csproj --configuration Release -p:Version="$pkg" --verbosity quiet --nologo
    mkdir -p /out/SDK_Binaries_CSharp
    cp "src/bin/Release/XenServer.NET.$pkg.nupkg" /out/SDK_Binaries_CSharp/

    # Every build of the C# SDK has this same version, so drop any copy NuGet cached from an earlier build.
    rm -rf /root/.nuget/packages/xenserver.net
    cd /build/powershell
    sed -i "s/@SDK_VERSION@/$pkg/" src/Connect-XenServer.cs
    # A nuget.config beside the project adds the C# SDK just built to the default package sources.
    printf "<configuration><packageSources><add key=\"local\" value=\"/out/SDK_Binaries_CSharp\" /></packageSources></configuration>" \
        > src/nuget.config
    dotnet add src package XenServer.NET --version "$pkg" >/dev/null
    dotnet build src/XenServerPowerShell.csproj --configuration Release -p:Version="$pkg" \
        -p:TargetFramework=net10.0 --verbosity quiet --nologo
    sed -i -e "s/@SDK_VERSION@/$VERSION/" -e "s/@PS_VERSION@/7.6/" XenServerPSModule.psd1
    o=/out/SDK_Binaries_XenServerPowerShell_NET10
    mkdir -p $o
    cp README.md LICENSE XenServerPowerShell.dll-Help.xml $o/
    cp src/bin/Release/net10.0/*.dll $o/
    cp *.ps1 *.ps1xml *.psd1 *.txt $o/
'
rm -rf "$out/source"

# 4. Python isn't built: take it from the checkout. Then stage the lot.
mkdir -p "$out/python/XenAPI"
cp "$src"/python3/examples/XenAPI/__init__.py "$src"/python3/examples/XenAPI/XenAPI.py "$out/python/XenAPI/"
echo "$src ${head}${dirty}" > "$out/BUILT-FROM"
"$root/tools/stage-ci-sdk.sh" --from "$out"
