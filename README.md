# v2rayH

A HarmonyOS / OpenHarmony port of [v2rayNG](https://github.com/2dust/v2rayNG): a
VLESS / VMess / Trojan / Shadowsocks client that drives a real VPN through the
in-tree [Xray-core](https://github.com/xtls/xray-core) kernel.

Traffic flow:

```
apps ──► vpn-tun (VpnExtensionAbility) ──► gVisor netstack (L3→L4)
     ──► Xray VLESS+REALITY outbound ──► internet
```

## Layout

| Path | What |
| --- | --- |
| `entry/src/main/ets/` | ArkTS UI, subscription parsing, VPN extension ability |
| `entry/src/main/cpp/` | NAPI module (`libentry.so`) that hosts the Go kernel |
| `native/libxray/` | Go wrapper + vendored, patched `xray-core` and `gvisor` |
| `native/build_libxray.sh` | rebuild `libxray.a` (openharmony/arm64) — Linux/CI |
| `native/build_libxray.ps1` | same, for a Windows host |
| `.github/workflows/build-libxray.yml` | CI that produces `libxray.a` |

## Native kernel

The kernel is built as a **c-archive** which CMake statically links into
`libentry.so`, so there is no runtime SONAME to ship.

Two things are needed to build it:

1. **ohos-go** — a Go toolchain that knows `GOOS=openharmony`/`GOARCH=arm64`.
   Prebuilt `linux-amd64` / `darwin-arm64` tarballs come from
   <https://github.com/sysit/ohos-go/releases>.
   (Stock Go cannot target OpenHarmony. The stock compiler also emits
   `R_AARCH64_TLS_TPREL64` initial-exec TLS relocations, which musl refuses at
   `dlopen`; ohos-go emits `R_AARCH64_TLSDESC` instead.)
2. **OpenHarmony SDK native toolchain** — `clang` + `sysroot` for
   `aarch64-linux-ohos`. Comes from either DevEco Studio
   (`sdk/default/openharmony/native/…`) or the public mirror
   <https://repo.huaweicloud.com/openharmony/os/>, where
   `ohos-sdk-windows_linux-public.tar.gz` contains a per-component
   `linux/native-*.zip`.

```bash
# Linux / CI
OHOS_GO=/path/to/ohos-go OHOS_SDK=/path/to/ohos-sdk ./native/build_libxray.sh

# Windows
.\native\build_libxray.ps1 -OHOS_GO C:\ohos-go -OHOS_SDK "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony"
```

Both copy the result into `entry/src/main/cpp/thirdparty/libxray/`
(`libs/arm64-v8a/libxray.a` + `include/libxray.h`), which is git-ignored —
`devecocli build` needs it present.

## Building the app

```bash
devecocli build
devecocli run --skip-build
```

## CI

`.github/workflows/build-libxray.yml` runs on manual dispatch, on
`native/**` changes, on release publishes, and weekly. It downloads the two
toolchains above (both cached), builds `libxray.a`, uploads it as an artifact,
and attaches it to the release. The weekly run also opens an issue when
`xtls/xray-core` publishes a newer tag than the one vendored in
`native/libxray/go.mod`.

Pin bumps live in `env:` at the top of that workflow
(`OHOS_GO_VERSION`, `OHOS_SDK_VERSION`, `XRAY_VERSION`).

> Note: CI only builds the native kernel. The HAP itself must be built locally
> because the HarmonyOS app toolchain ships with DevEco Studio.

## OpenHarmony patches

`native/libxray/go.mod` redirects `github.com/xtls/xray-core` and
`gvisor.dev/gvisor` at the vendored copies via `replace`. Three overlays make
them build and run on OpenHarmony — see `native/README.md`.

For the full list of things that went wrong while getting this to build and run
(initial-exec TLS vs musl, the cgo `CC` wrapper, the gVisor `fstat` denial, the
routing loop, the CI packaging traps), see [`docs/build-notes.md`](docs/build-notes.md).
