#!/usr/bin/env bash
# build_libxray.sh
# Rebuild the Xray kernel (libxray.a) for openharmony/arm64 and copy it into
# entry/src/main/cpp/thirdparty/libxray/.
#
# Prerequisites:
#   OHOS_GO   - ohos-go (OpenHarmony Go) toolchain root   [default /opt/ohos-go]
#   OHOS_SDK  - OpenHarmony / HarmonyOS SDK root          [default /opt/ohos-sdk]
#   STOCK_GO  - a host Go (used only to build the ccwrap helper) [default go]
#
# Usage: OHOS_GO=... OHOS_SDK=... ./build_libxray.sh

set -euo pipefail

OHOS_GO="${OHOS_GO:-/opt/ohos-go}"
OHOS_SDK="${OHOS_SDK:-/opt/ohos-sdk}"
STOCK_GO="${STOCK_GO:-go}"

NATIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$NATIVE_DIR/libxray"
TOOLS_DIR="$NATIVE_DIR/tools"
CCWRAP_SRC="$TOOLS_DIR/ccwrap/ccwrap.go"
CCWRAP_BIN="$TOOLS_DIR/bin/ccwrap"
AR_DIR="$TOOLS_DIR/bin"
AR_BIN="$AR_DIR/ar"

OHOS_GO_BIN="$OHOS_GO/bin/go"
LLVM_AR="$OHOS_SDK/native/llvm/bin/llvm-ar"
CLANG="$OHOS_SDK/native/llvm/bin/clang"
SYSROOT="$OHOS_SDK/native/sysroot"

die() { echo "error: $*" >&2; exit 1; }

[ -x "$OHOS_GO_BIN" ] || die "ohos-go toolchain not found: $OHOS_GO_BIN (set OHOS_GO)"
[ -x "$CLANG" ] || die "clang not found: $CLANG (set OHOS_SDK)"
[ -d "$SYSROOT" ] || die "sysroot not found: $SYSROOT (set OHOS_SDK)"
[ -x "$LLVM_AR" ] || die "llvm-ar not found: $LLVM_AR (set OHOS_SDK)"

# 1. build ccwrap (host helper that injects --target/--sysroot into clang)
mkdir -p "$TOOLS_DIR/bin"
if [ ! -x "$CCWRAP_BIN" ]; then
  echo "[1/4] building ccwrap"
  "$STOCK_GO" build -o "$CCWRAP_BIN" "$CCWRAP_SRC"
fi

# 2. expose llvm-ar as `ar` on PATH (Go's c-archive link step shells out to `ar`)
if [ ! -x "$AR_BIN" ]; then
  echo "[2/4] exposing llvm-ar as ar"
  mkdir -p "$AR_DIR"
  ln -sf "$LLVM_AR" "$AR_BIN"
fi

# 3. cross-compile libxray.a
echo "[3/4] cross-compiling libxray.a (openharmony/arm64, c-archive)"
(
  cd "$LIB_DIR"
  OHOS_SDK="$OHOS_SDK" \
  GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 \
  CC="$CCWRAP_BIN" CGO_CFLAGS="" CGO_LDFLAGS="" \
  PATH="$AR_DIR:$PATH" \
  "$OHOS_GO_BIN" build -buildmode=c-archive -o libxray.a .
)

# 4. copy into the app
echo "[4/4] copying libxray.a + libxray.h into the project"
CPP_THIRD="$NATIVE_DIR/../entry/src/main/cpp/thirdparty/libxray"
mkdir -p "$CPP_THIRD/libs/arm64-v8a" "$CPP_THIRD/include"
cp "$LIB_DIR/libxray.a" "$CPP_THIRD/libs/arm64-v8a/libxray.a"
cp "$LIB_DIR/libxray.h" "$CPP_THIRD/include/libxray.h"

echo "done -> $CPP_THIRD"
