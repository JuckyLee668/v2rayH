# native/

The native side of v2rayH: a Go c-archive (`libxray.a`) that wraps
[Xray-core](https://github.com/xtls/xray-core) behind a small C API consumed by
`entry/src/main/cpp/napi_init.cpp`.

## Contents

| Path | What |
| --- | --- |
| `libxray/main.go` | C ABI: `StartXray` / `StopXray` / `IsXrayRunning` / `GetLastError` / `StartVpnTun` / `StopVpn` / `MeasureDelay` / `MeasureDownload` |
| `libxray/go.mod` | module + `replace` directive pointing at the vendored fork |
| `libxray/xray-core/` | vendored xray-core v1.261029.0 + OpenHarmony overlay |
| `tools/ccwrap/ccwrap.go` | host helper that re-invokes the SDK clang with `--target`/`--sysroot` |
| `build_libxray.sh` / `.ps1` | one-click rebuild for Linux / Windows |

## Why vendored fork

`go.mod` pins the dependency to a local directory:

```
replace github.com/xtls/xray-core => ./xray-core
```

so the overlays below survive `go mod` operations, and the exact kernel that
ships is the exact kernel in the tree.

Since xray-core v26.10.29 the tun proxy no longer uses gVisor — it ships a
custom lightweight TCP/IP stack (`proxy/tun/stack.go`, `tcp_lightweight.go`) —
so no gvisor copy is vendored anymore.

## The two OpenHarmony overlays

Everything else in `xray-core/` is upstream.

**1. `xray-core/proxy/tun/tun_openharmony.go` (new file)**

```
//go:build openharmony
```

An fd-based tun handler modelled on `tun_android.go`: the app passes the tun
file descriptor handed out by `VpnExtensionAbility` straight into it, via the
`xray.tun.fd` environment variable. It embeds `fdTun` (from `tun_fd.go`, which
is compiled because ohos-go sets the `linux` build tag), provides
`setinterface` / `findOutboundInterface` like the Android file does, and
excludes itself from any netlink use.

**2. `xray-core/proxy/tun/tun_linux.go` (build tag)**

```
- //go:build linux && !android
+ //go:build linux && !android && !openharmony
```

ohos-go reports `runtime.GOOS == "linux"` for OpenHarmony (the port keeps every
"is this Linux?" check true and layers `runtime.IsOpenharmony` on top), so
without this the Linux handler — which wants `netlink` — is compiled in
alongside the OpenHarmony one and the two `NewTun` implementations collide.

The former third overlay (`gvisor/pkg/tcpip/link/fdbased/endpoint.go`,
`isSocketFD` tolerating `fstat` EACCES on the tun fd) is gone together with the
vendored gvisor: the new lightweight stack reads the fd through `os.NewFile`
and never `fstat`s it.

## Updating Xray

1. Re-vendor `xray-core` at the new tag (module version `v1.YYMMDD.0` for
   release tag `vYY.M.DD`).
2. Re-apply overlays 1–2.
3. Bump `XRAY_VERSION` in `.github/workflows/build-libxray.yml` and
   `XRAY_CORE_VERSION` in `entry/src/main/cpp/napi_init.cpp`.

The `check-upstream` CI job opens an issue when a newer tag appears, so step 1
is not something you have to poll for.
