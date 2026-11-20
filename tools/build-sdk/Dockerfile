# The build environment for xen-api's SDK generators, set up the way xen-api's CI does it
# (.github/workflows/setup-xapi-environment): xs-opam's packages on OCaml 4.14, plus a JDK and Maven to
# build the Java SDK.
#
# Built by build-sdk.sh with only xen-api's opam/ directory as context, so the slow dependency install is
# cached in the image until those files change.
FROM ocaml/opam:ubuntu-22.04-ocaml-4.14

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-17-jdk-headless maven python3 \
 && rm -rf /var/lib/apt/lists/*
# Part of the datamodel's input, fetched by the CI setup too.
RUN mkdir -p /opt/xensource/sm \
 && curl -fsSL -o /opt/xensource/sm/XE_SR_ERRORCODES.xml \
      https://raw.githubusercontent.com/xapi-project/sm/master/libs/sm/core/XE_SR_ERRORCODES.xml

USER opam
# xs-opam alone, as in the CI: it pins the versions xen-api builds with, and the base image's default
# repository would otherwise supply newer, incompatible ones (ambient-context 0.2, without thread_local).
RUN opam repo add xs-opam https://github.com/xapi-project/xs-opam.git --set-default --all-switches \
 && opam repo remove default --all \
 && opam update
COPY --chown=opam opam/ /home/opam/deps/opam/
WORKDIR /home/opam/deps
# --depext-only installs the system packages the dependencies need, so it needs apt's package lists.
RUN sudo apt-get update \
 && opam install . --depext-only -y \
 && opam install . --deps-only -y \
 && sudo rm -rf /var/lib/apt/lists/*
