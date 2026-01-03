ARG ALPINE_BUILD_TAG=3.23
ARG LLVM_VERSION=21.1.8
ARG XX_VERSION=1.9.0
ARG BOOTSTRAP_SOURCE=bootstrap_builder

FROM --platform=$BUILDPLATFORM registry.alpinelinux.org/img/alpine:${ALPINE_BUILD_TAG} AS base_builder
RUN mkdir /work
WORKDIR /work
RUN apk add --no-cache ccache cmake clang curl gpg gpg-agent lld llvm ninja-is-really-ninja python3 xz
ARG LLVM_VERSION
RUN --mount=type=bind,target=/tmp/context/llvm-release-keys.asc,source=llvm-release-keys.asc <<EOT
set -ex
gpg --import /tmp/context/llvm-release-keys.asc
curl -fsSLo /tmp/llvm-project.tar.xz.sig --retry 5 "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz.sig"
curl -fsSLo /tmp/llvm-project.tar.xz     --retry 5 "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz"
gpg --verify /tmp/llvm-project.tar.xz.sig /tmp/llvm-project.tar.xz
gpgconf --kill gpg-agent
mkdir llvm-project
tar --strip-components 1 -xf /tmp/llvm-project.tar.xz -C llvm-project
rm /tmp/llvm-project*
rm -rf ~/.gnupg
EOT

FROM base_builder AS bootstrap_builder
RUN apk add --no-cache libstdc++-dev musl-dev zlib-dev zstd-dev
COPY staged-build.cmake /work/staged-build.cmake
RUN --mount=type=cache,target=/tmp/ccache-bootstrap <<EOT
set -ex
# use SOURCE_DATE_EPOCH=0 to get reproducible builds for the stage 1 compiler
export SOURCE_DATE_EPOCH=0
LLVM_CCACHE_DIR=/tmp/ccache-bootstrap
LLVM_CCACHE_MAXSIZE=350M
ccache -d ${LLVM_CCACHE_DIR} -M ${LLVM_CCACHE_MAXSIZE} --zero-stats
cmake -G Ninja -B bootstrap -S llvm-project/llvm \
      -DLLVM_CCACHE_BUILD=ON \
      -DLLVM_CCACHE_DIR=${LLVM_CCACHE_DIR} \
      -DLLVM_CCACHE_MAXSIZE=${LLVM_CCACHE_MAXSIZE} \
      -C staged-build.cmake
cmake --build bootstrap \
      --target clang \
      --target lld \
      --target llvm-addr2line \
      --target llvm-ar \
      --target llvm-config \
      --target llvm-cxxfilt \
      --target llvm-dlltool \
      --target llvm-nm \
      --target llvm-objcopy \
      --target llvm-objdump \
      --target llvm-ranlib \
      --target llvm-readelf \
      --target llvm-readobj \
      --target llvm-size \
      --target llvm-strings \
      --target llvm-strip \
      --target llvm-symbolizer
ccache -d ${LLVM_CCACHE_DIR} -M ${LLVM_CCACHE_MAXSIZE} --show-stats
# delete unused object files
find bootstrap -path '*.dir/*.o' -delete
EOT

FROM scratch AS bootstrap_artifact
COPY --link --from=bootstrap_builder /work/bootstrap /work/bootstrap

FROM scratch AS artifact
ADD bootstrap_artifact.tar.xz /

FROM ${BOOTSTRAP_SOURCE} AS bootstrap_source

FROM --platform=$BUILDPLATFORM tonistiigi/xx:${XX_VERSION} AS xx

FROM base_builder AS builder
COPY --from=xx / /
ARG TARGETPLATFORM
RUN xx-info env
RUN xx-apk add --no-cache gcc libstdc++-dev musl-dev zlib-dev zlib-static zstd-dev zstd-static
RUN xx-clang --print-cmake-defines
COPY --link --from=bootstrap_source /work/bootstrap /work/bootstrap
ENV PATH="/work/bootstrap/bin:$PATH"
COPY staged-build.cmake /work/staged-build.cmake
RUN --mount=type=cache,target=/tmp/ccache-build <<EOT
set -ex
# the bootstrapped compiler is not mtime friendly as it can also be rebuilt
# even if the binary is identical in the end, use content hash instead
export CCACHE_COMPILERCHECK=content
LLVM_CCACHE_DIR=/tmp/ccache-build
LLVM_CCACHE_MAXSIZE=350M
ccache -d ${LLVM_CCACHE_DIR} -M ${LLVM_CCACHE_MAXSIZE} --zero-stats
cmake -G Ninja -B build -S llvm-project/llvm \
      -DCMAKE_INSTALL_PREFIX=/opt/clang \
      -DCMAKE_SYSROOT="$(xx-info sysroot)" \
      -DLLVM_CCACHE_BUILD=ON \
      -DLLVM_CCACHE_DIR=${LLVM_CCACHE_DIR} \
      -DLLVM_CCACHE_MAXSIZE=${LLVM_CCACHE_MAXSIZE} \
      -DLLVM_HOST_TRIPLE="$(xx-info triple)" \
      -DLLVM_NATIVE_TOOL_DIR=/work/bootstrap/bin \
      -C staged-build.cmake
cmake --build build \
      --target clang \
      --target lld \
      --target llvm-addr2line \
      --target llvm-ar \
      --target llvm-config \
      --target llvm-cxxfilt \
      --target llvm-dlltool \
      --target llvm-dwp \
      --target llvm-nm \
      --target llvm-objcopy \
      --target llvm-objdump \
      --target llvm-ranlib \
      --target llvm-readelf \
      --target llvm-readobj \
      --target llvm-size \
      --target llvm-strings \
      --target llvm-strip \
      --target llvm-symbolizer
ccache -d ${LLVM_CCACHE_DIR} -M ${LLVM_CCACHE_MAXSIZE} --show-stats
EOT
RUN <<EOT
set -ex
cmake --install build --strip
rm -rf /opt/clang/bin/hmaptool /opt/clang/lib/cmake
EOT
# check all binaries are statically linked
RUN xx-verify --static /opt/clang/bin/*
# check expected files in distribution
RUN --mount=type=bind,target=/tmp/context/expected-files.txt,source=expected-files.txt <<EOT
set -ex
find /opt/clang | sort | tee /tmp/files.txt
diff -u /tmp/context/expected-files.txt /tmp/files.txt
rm /tmp/files.txt
EOT
# minimal check that binaries are working
RUN <<EOT
set -ex
/opt/clang/bin/ld.lld --version
for FILE in $(find /opt/clang/bin -type f -not -name 'lld'); do
  ${FILE} --version || exit 1
done
EOT

FROM scratch
COPY --from=builder /opt/clang /opt/clang
