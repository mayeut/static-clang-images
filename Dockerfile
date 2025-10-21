ARG ALPINE_BUILD_TAG=3.22
ARG LLVM_VERSION=21.1.4
ARG XX_VERSION=1.8.0

FROM --platform=$BUILDPLATFORM tonistiigi/xx:${XX_VERSION} AS xx

FROM --platform=$BUILDPLATFORM registry.alpinelinux.org/img/alpine:${ALPINE_BUILD_TAG} AS builder
ARG LLVM_VERSION
ARG XX_VERSION
ARG TARGETPLATFORM
COPY --from=xx / /
RUN mkdir /work
WORKDIR /work
RUN xx-info env
RUN apk add --no-cache ninja cmake git clang lld llvm python3
RUN git clone -b llvmorg-${LLVM_VERSION} --depth=1 https://github.com/llvm/llvm-project.git
RUN xx-apk add --no-cache gcc libstdc++-dev musl-dev zlib-dev zlib-static zstd-dev zstd-static
RUN apk add --no-cache gcc libstdc++-dev musl-dev zlib-dev zlib-static zstd-dev zstd-static
RUN xx-clang --print-cmake-defines
RUN cmake \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSROOT="$(xx-info sysroot)" \
    $(xx-clang --print-cmake-defines) \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
    -DCMAKE_AR=/usr/bin/llvm-ar \
    -DCMAKE_OBJDUMP=/usr/bin/llvm-objdump \
    -DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
    -DCMAKE_STRIP=/usr/bin/llvm-strip \
    -DLLVM_HOST_TRIPLE="$(xx-info triple)" \
    -DCROSS_TOOLCHAIN_FLAGS_NATIVE='-DCMAKE_ASM_COMPILER=clang;-DCMAKE_C_COMPILER=clang;-DCMAKE_CXX_COMPILER=clang++' \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_INSTALL_PREFIX="/opt/clang" \
    -DCMAKE_LINK_SEARCH_START_STATIC=ON \
    -DCMAKE_EXE_LINKER_FLAGS='-static-libgcc -static' \
    -DCMAKE_FIND_LIBRARY_SUFFIXES='.a' \
    -DLLVM_ENABLE_PROJECTS='clang;lld' \
    -DLLVM_TARGETS_TO_BUILD='X86;SystemZ;RISCV;PowerPC;ARM;AArch64;LoongArch' \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    -DZLIB_USE_STATIC_LIBS=ON \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON \
    -DLLVM_INSTALL_UTILS=OFF \
    -DLLVM_USE_LINKER=lld \
    -G Ninja -B build -S llvm-project/llvm
RUN cmake --build build \
    --target install-clang-stripped \
    --target install-clang-resource-headers-stripped \
    --target install-lld-stripped \
    --target install-llvm-as-stripped \
    --target install-addr2line-stripped \
    --target install-ar-stripped \
    --target install-c++filt-stripped \
    --target install-dwp-stripped \
    --target install-nm-stripped \
    --target install-objcopy-stripped \
    --target install-objdump-stripped \
    --target install-ranlib-stripped \
    --target install-readelf-stripped \
    --target install-size-stripped \
    --target install-strings-stripped \
    --target install-strip-stripped
RUN xx-verify --static /opt/clang/bin/*

FROM scratch
COPY --from=builder /opt/clang /opt/clang
