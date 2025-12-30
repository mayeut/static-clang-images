ARG ALPINE_BUILD_TAG=3.23
ARG LLVM_VERSION=21.1.8
ARG XX_VERSION=1.9.0

FROM --platform=$BUILDPLATFORM tonistiigi/xx:${XX_VERSION} AS xx

FROM --platform=$BUILDPLATFORM registry.alpinelinux.org/img/alpine:${ALPINE_BUILD_TAG} AS builder
ARG LLVM_VERSION
ARG XX_VERSION
ARG TARGETPLATFORM
COPY --from=xx / /
RUN mkdir /work
WORKDIR /work
RUN xx-info env
RUN apk add --no-cache cmake clang curl gpg gpg-agent lld llvm ninja python3 xz
RUN xx-apk add --no-cache gcc libstdc++-dev musl-dev zlib-dev zlib-static zstd-dev zstd-static
RUN apk add --no-cache gcc libstdc++-dev musl-dev zlib-dev zlib-static zstd-dev zstd-static
RUN xx-clang --print-cmake-defines
RUN --mount=type=bind,target=/tmp/context/llvm-release-keys.asc,source=llvm-release-keys.asc \
    gpg --import /tmp/context/llvm-release-keys.asc && \
    curl -fsSLo /tmp/llvm-project.tar.xz.sig "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz.sig" && \
    curl -fsSLo /tmp/llvm-project.tar.xz "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz" && \
    gpg --verify /tmp/llvm-project.tar.xz.sig /tmp/llvm-project.tar.xz && \
    mkdir llvm-project && \
    tar --strip-components 1 -xf /tmp/llvm-project.tar.xz -C llvm-project && \
    rm /tmp/llvm-project*
RUN cmake \
    -DBUILD_SHARED_LIBS=OFF \
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
    -DCROSS_TOOLCHAIN_FLAGS_NATIVE='-DCMAKE_ASM_COMPILER=clang;-DCMAKE_C_COMPILER=clang;-DCMAKE_CXX_COMPILER=clang++' \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="/opt/clang" \
    -DCMAKE_LINK_SEARCH_START_STATIC=ON \
    -DCMAKE_EXE_LINKER_FLAGS='-static-libgcc -static' \
    -DCMAKE_FIND_LIBRARY_SUFFIXES='.a' \
    -DZLIB_USE_STATIC_LIBS=ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DCLANG_ENABLE_OBJC_REWRITER=OFF \
    -DCLANG_TOOL_APINOTES_TEST_BUILD=OFF \
    -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_FORMAT_BUILD=OFF \
    -DCLANG_TOOL_CLANG_INSTALLAPI_BUILD=OFF \
    -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_NVLINK_WRAPPER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_OFFLOAD_BUNDLER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_OFFLOAD_PACKAGER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_REFACTOR_BUILD=OFF \
    -DCLANG_TOOL_CLANG_REPL_BUILD=OFF \
    -DCLANG_TOOL_CLANG_SCAN_DEPS_BUILD=OFF \
    -DCLANG_TOOL_CLANG_SYCL_LINKER_BUILD=OFF \
    -DCLANG_TOOL_DIAGTOOL_BUILD=OFF \
    -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
    -DCLANG_TOOL_OFFLOAD_ARCH_BUILD=OFF \
    -DLLVM_APPEND_VC_REV=OFF \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_CURL=OFF \
    -DLLVM_ENABLE_EH=OFF \
    -DLLVM_ENABLE_FFI=OFF \
    -DLLVM_ENABLE_HTTPLIB=OFF \
    -DLLVM_ENABLE_LIBCXX=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_PIC=ON \
    -DLLVM_ENABLE_PLUGINS=OFF \
    -DLLVM_ENABLE_PROJECTS='clang;lld' \
    -DLLVM_ENABLE_RTTI=OFF \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_HOST_TRIPLE="$(xx-info triple)" \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_UTILS=OFF \
    -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON \
    -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
    -DLLVM_TARGETS_TO_BUILD='X86;SystemZ;RISCV;PowerPC;ARM;AArch64;LoongArch' \
    -DLLVM_TOOL_LLVM_CONFIG_BUILD=OFF \
    -DLLVM_TOOL_LLVM_COV_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MCA_BUILD=OFF \
    -DLLVM_TOOL_LLVM_ML_BUILD=OFF \
    -DLLVM_TOOL_LLVM_PDBUTIL_BUILD=OFF \
    -DLLVM_TOOL_LLVM_PROFDATA_BUILD=OFF \
    -DLLVM_TOOL_LLVM_PROFGEN_BUILD=OFF \
    -DLLVM_TOOL_LLVM_RC_BUILD=OFF \
    -DLLVM_TOOL_LTO_BUILD=OFF \
    -DLLVM_TOOL_OPT_VIEWER_BUILD=OFF \
    -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
    -DLLVM_USE_LINKER=lld \
    -G Ninja -B build -S llvm-project/llvm

RUN cmake \
      --build build \
      --target clang \
      --target lld \
      --target llvm-ar \
      --target llvm-cxxfilt \
      --target llvm-dwp \
      --target llvm-nm \
      --target llvm-objcopy \
      --target llvm-objdump \
      --target llvm-readobj \
      --target llvm-size \
      --target llvm-strings \
      --target llvm-symbolizer

RUN cmake --install build --strip && rm -rf /opt/clang/bin/hmaptool /opt/clang/lib/cmake
RUN xx-verify --static /opt/clang/bin/*

FROM scratch
COPY --from=builder /opt/clang /opt/clang
