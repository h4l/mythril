# syntax=docker/dockerfile:1

# Here we extract dependency version numbers from the Poetry lockfile. We use
# the number of mythril to determine the tag of the main image. And we use the
# requirements.txt file to define the exact python packages we install in the
# main image to be from the listed versions. (The requirements file contains
# fixed versions and hashes of acceptable artefacts.)
FROM python:3.11-slim AS generate-locked-versions
RUN pip install 'poetry >=1, <2'
WORKDIR /project
COPY pyproject.toml poetry.lock /project/
# Fail if the lockfile is not in sync with pyproject.toml
RUN poetry lock --check
RUN poetry export --format=requirements.txt \
  # remove line continuations so that we can grep lines from the file later
  |  python -c 'from sys import stdin; print(stdin.read().replace("\\\n", ""))' \
  > requirements.txt
RUN poetry export --format=constraints.txt > constraints.txt
COPY gen_version_vars.py /project
RUN python gen_version_vars.py > docker-bake.versions.json


FROM scratch AS locked-versions
COPY --from=generate-locked-versions \
  /project/requirements.txt /project/constraints.txt /project/docker-bake.versions.json /


# The Python version needs to be the version of Python used in the Debian
# version, otherwise the built wheels won't be compatible.
FROM python:3.9-slim AS python-slim

# Because we're cross-compiling, we always want to be running the native arch of
# the builder for everything except the final output stages.
FROM --platform=${BUILDARCH} debian:bullseye as base
ARG BUILDARCH TARGETARCH

# Define envars for the alternative arch names some programs use
FROM base AS build-for-amd64-from-amd64
ARG ALT_TARGETARCH=x86_64 ALT_BUILDARCH=x86_64
FROM base AS build-for-arm64-from-arm64
ARG ALT_TARGETARCH=aarch64 ALT_BUILDARCH=aarch64
FROM base AS build-for-amd64-from-arm64
ARG ALT_TARGETARCH=x86_64 ALT_BUILDARCH=aarch64
FROM base AS build-for-arm64-from-amd64
ARG ALT_TARGETARCH=aarch64 ALT_BUILDARCH=x86_64


FROM build-for-${TARGETARCH:?}-from-${BUILDARCH:?} AS build-base
SHELL ["bash", "-xeuo", "pipefail", "-c"]


FROM build-base AS rust
# Enable cargo sparse index protocol to prevent it using large amounts of memory
# in docker builds, and speed up builds by downloading less.
# https://blog.rust-lang.org/inside-rust/2023/01/30/cargo-sparse-protocol.html
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
RUN apt-get update && apt-get install -y curl
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
    -y \
    --target ${ALT_TARGETARCH:?}-unknown-linux-gnu
# Tell cargo to use C compiler matching the target arch when linking, otherwise
# it'll use the $BUILDARCH compiler, which is wrong when cross-compiling.
COPY <<-"EOT" /root/.cargo/config.toml
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"
[target.x86_64-unknown-linux-gnu]
linker = "x86_64-linux-gnu-gcc"
EOT


FROM build-base AS cross-build
# Using debian's multi-arch support, we install python in the foreign
# architecture. We'll rely on emulation to run pip, etc, but the actual
# compilation (the slow part) will run without emulation on native compiler
# executables.
RUN dpkg --add-architecture "${TARGETARCH:?}"
RUN apt-get update
RUN apt-get install -y \
    "crossbuild-essential-${TARGETARCH:?}" \
    python3-dev:${TARGETARCH:?} python3-venv:${TARGETARCH:?} \
    cmake

# Use the target's compiler when compiling
ENV CC=/usr/bin/${ALT_TARGETARCH:?}-linux-gnu-gcc \
    CXX=/usr/bin/${ALT_TARGETARCH:?}-linux-gnu-g++ \
    # This prevents the python cmake module building from source when installing
    # (It fails to build because it hardcodes strip executable to just "strip",
    # so it uses the native version not the cross toolchain version. Could work
    # around by aliasing the right strip, but we don't need to build it anyway.)
    SKBUILD_CONFIGURE_OPTIONS=-DBUILD_CMAKE_FROM_SOURCE:BOOL=OFF \
    CMAKE_BUILD_PARALLEL_LEVEL=3

RUN python3 -m venv /build_env
ENV PATH=/build_env/bin:$PATH
# auditwheel is pypa's tool to fix wheel metadata. It seems to need to be run in
# the target arch's python, otherwise it adds wheel tags for the build.
RUN pip3 install --upgrade pip auditwheel

# We need rust to build blake2b
COPY --from=rust /root/.cargo /root/.cargo
COPY --from=rust /root/.rustup /root/.rustup
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse \
    PATH=/root/.cargo/bin:$PATH \
    # Tell pyo3 to use our target arch python when compiling
    PYO3_CROSS_LIB_DIR=/usr/lib

WORKDIR /wheels


FROM cross-build AS z3-solver-wheel-build
RUN --mount=from=locked-versions,source=/,target=/run/locked-versions \
  z3_version=$(grep -P '^z3-solver' /run/locked-versions/requirements.txt) && \
  pip3 -vv wheel --constraint /run/locked-versions/constraints.txt \
    --requirement <(echo "${z3_version:?}")
# Prior to 4.12.2 z3-solver didn't tag arm64 wheels with valid metadata, so
# auditwheel was needed to install them. It's no longer essential, but doesn't
# hurt.
RUN mkdir tmp && mv *.whl tmp && auditwheel addtag -w . tmp/*.whl && rm -r tmp


FROM cross-build AS blake2b-wheel-build
# blake2b doesn't publish source tarballs on pypi, and doesn't publish arm64
# builds, so we build from git for both platforms for consistency.

# blake2b is implemented in rust and builds with maturin. We need to tell
# maturin to cross-compile using --target, but here pip invokes maturin for us,
# so we need to use an envar to control the target arch.
ENV CARGO_BUILD_TARGET=${ALT_TARGETARCH:?}-unknown-linux-gnu
# We can't use the requirements file for blake2b because we install from the
# source repo. However, the source repo tag is fixed via the lockfile, and the
# actual resolved sha is logged in the image's provenance data created by docker
# buildx.
RUN --mount=from=blake2b-src,source=/,target=/wheels/blake2b-src,rw \
    pip3 -vv wheel ./blake2b-src


FROM cross-build AS mythril-wheel-build
# cython is optional but can be used to build some wheels, such as cytoolz
RUN pip install cython
RUN --mount=from=locked-versions,source=requirements.txt,target=/run/requirements.txt \
    # Ignore blake2b and z3-solver as we've already built them. Ignore mythril
    # as we're installing it from the source repo.
    grep -v -P '^(blake2b|z3-solver|mythril)' /run/requirements.txt \
    > /run/requirements-remaining.txt
RUN pip wheel -r /run/requirements-remaining.txt

RUN --mount=from=mythril-src,source=/,target=/mythril-src,rw \
    pip wheel --no-deps /mythril-src

COPY --from=blake2b-wheel-build /wheels /wheels
COPY --from=z3-solver-wheel-build /wheels /wheels


# Solidity Compiler Version Manager. This provides cross-platform solc builds.
# It's used by foundry to provide solc. https://github.com/roynalnaruto/svm-rs
FROM cross-build AS solidity-compiler-version-manager
RUN cargo install --target ${ALT_TARGETARCH:?}-unknown-linux-gnu svm-rs
# put the binaries somewhere obvious for later stages to use
RUN mkdir -p /svm-rs/bin && cd ~/.cargo/bin/ && cp svm solc /svm-rs/bin/


FROM python-slim AS myth
# Space-separated version string without leading 'v' (e.g. "0.4.21 0.4.22")
ARG INSTALLED_SOLC_VERSIONS

COPY --from=solidity-compiler-version-manager /svm-rs/bin/* /usr/local/bin/

RUN --mount=from=mythril-wheel-build,source=/wheels,target=/wheels \
  export PYTHONDONTWRITEBYTECODE=1 && pip install --no-cache-dir /wheels/*.whl

RUN adduser --disabled-password mythril
USER mythril
WORKDIR /home/mythril

# pre-install solc versions
RUN [ "${INSTALLED_SOLC_VERSIONS:?}" = ":none:" ] \
    || svm install ${INSTALLED_SOLC_VERSIONS}

COPY --from=mythril-src --chown=mythril:mythril \
  ./mythril/support/assets/signatures.db \
  /home/mythril/.mythril/signatures.db

COPY --chown=root:root --chmod=755 docker-entrypoint.sh /
COPY --chown=root:root --chmod=755 \
  sync-svm-solc-versions-with-solcx.sh \
  /usr/local/bin/sync-svm-solc-versions-with-solcx
ENTRYPOINT ["/docker-entrypoint.sh"]


# Basic sanity checks to make sure the build is functional
FROM myth AS myth-smoke-test-execution
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
WORKDIR /smoke-test
COPY --chmod=755 <<"EOT" /smoke-test.sh
#!/usr/bin/env bash
set -x -euo pipefail

# Check solcx knows about svm solc versions
svm install 0.5.0
sync-svm-solc-versions-with-solcx
python -c '
import solcx
print("\n".join(str(v) for v in solcx.get_installed_solc_versions()))
' | grep -P '^0\.5\.0$' || {
  echo "solcx did not report svm-installed solc version";
  exit 1
}

# Check myth can run
myth version
myth function-to-hash 'function transfer(address _to, uint256 _value) public returns (bool success)'
(myth safe-functions /solidity_examples/token.sol || true) | tee safe-functions.log
grep '3 functions are deemed safe in this contract:' safe-functions.log || {
  echo "Failed to detect safe functions in token.sol";
  exit 1
}

# Check that the entrypoint works
[[ $(/docker-entrypoint.sh version) == $(myth version) ]]
[[ $(/docker-entrypoint.sh echo hi) == hi ]]
[[ $(/docker-entrypoint.sh bash -c "printf '>%s<' 'foo bar'") == ">foo bar<" ]]
EOT

RUN --mount=from=mythril-src,source=./solidity_examples,target=/solidity_examples \
  /smoke-test.sh 2>&1 | tee smoke-test.log


FROM scratch as myth-smoke-test
COPY --from=myth-smoke-test-execution /smoke-test/* /
