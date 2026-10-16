# native/

The native side of v2rayH: a Go c-archive (`libxray.a`) that wraps
[Xray-core](https://github.com/xtls/xray-core) behind a small C API consumed by
`entry/src/main/cpp/napi_init.cpp`.

## Contents

| Path | What |
| --- | --- |
| `libxray/main.go` | C ABI: `StartXray` / `StopXray` / `IsXrayRunning` / `GetLastError` / `StartVpnTun` / `StopVpn` / `MeasureDelay` |
| `libxray/go.mod` | module + `replace` directives pointing at the vendored forks |
| `libxray/xray-core/` | vendored xray-core v1.260327.0 + OpenHarmony overlay |
| `libxray/gvisor/` | vendored gvisor + OpenHarmony overlay |
| `tools/ccwrap/ccwrap.go` | host helper that re-invokes the SDK clang with `--target`/`--sysroot` |
| `build_libxray.sh` / `.ps1` | one-click rebuild for Linux / Windows |

## Why vendored forks

`go.mod` pins both dependencies to local directories:

```
replace github.com/xtls/xray-core => ./xray-core
replace gvisor.dev/gvisor        => ./gvisor
```

so the overlays below survive `go mod` operations, and the exact kernel that
ships is the exact kernel in the tree.

## The three OpenHarmony overlays

Everything else in `xray-core/` and `gvisor/` is upstream.

**1. `xray-core/proxy/tun/tun_openharmony.go` (new file)**

```
//go:build openharmony
```

An fd-based tun handler modelled on `tun_android.go` — the app passes the tun
file descriptor handed out by `VpnExtensionAbility` straight into it.

**2. `xray-core/proxy/tun/tun_linux.go` (build tag)**

```
- //go:build linux && !android
+ //go:build linux && !android && !openharmony
```

ohos-go reports `runtime.GOOS == "linux"` for OpenHarmony (the port keeps every
"is this Linux?" check true and layers `runtime.IsOpenharmony` on top), so
without this the Linux handler — which wants `netlink` — is compiled in
alongside the new one.

**3. `gvisor/pkg/tcpip/link/fdbased/endpoint.go` (`isSocketFD`, ~line 402)**

```go
if err := unix.Fstat(fd, &stat); err != nil {
	return false, nil   // OpenHarmony: fstat on the VPN tun fd may fail EACCES
}
```

OpenHarmony denies `fstat` on the tun fd the VPN extension created while still
allowing `read`/`write`. Upstream treats the error as fatal; returning
`(false, nil)` makes the endpoint use the `readv()` dispatcher, which is what a
tun device needs anyway.

## Updating Xray

1. Re-vendor `xray-core` (and `gvisor`) at the new tag.
2. Re-apply overlays 1–3.
3. Bump `XRAY_VERSION` in `.github/workflows/build-libxray.yml`.

The `check-upstream` CI job opens an issue when a newer tag appears, so step 1
is not something you have to poll for.
