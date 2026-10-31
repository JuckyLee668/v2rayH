module libxray

go 1.27.0

require (
	github.com/sagernet/sing-box v1.14.4
	github.com/xtls/xray-core v1.261029.0
)

replace github.com/xtls/xray-core => ./xray-core

require (
	github.com/ajg/form v1.5.1 // indirect
	github.com/andybalholm/brotli v1.2.3 // indirect
	github.com/apernet/quic-go v0.61.1-0.20260806010916-184d081eef3e // indirect
	github.com/caddyserver/certmagic v0.25.3-0.20260421143802-60d9d8b415d6 // indirect
	github.com/caddyserver/zerossl v0.1.5 // indirect
	github.com/database64128/netx-go v0.1.1 // indirect
	github.com/database64128/tfo-go/v2 v2.3.2 // indirect
	github.com/florianl/go-nfqueue/v2 v2.1.0 // indirect
	github.com/fsnotify/fsnotify v1.9.0 // indirect
	github.com/ghodss/yaml v1.0.1-0.20220118164431-d8423dcdf344 // indirect
	github.com/go-chi/chi/v5 v5.2.5 // indirect
	github.com/go-chi/render v1.0.3 // indirect
	github.com/go-ole/go-ole v1.3.0 // indirect
	github.com/gobwas/httphead v0.1.0 // indirect
	github.com/gobwas/pool v0.2.1 // indirect
	github.com/godbus/dbus/v5 v5.2.2 // indirect
	github.com/gofrs/uuid/v5 v5.5.1 // indirect
	github.com/google/btree v1.1.3 // indirect
	github.com/google/go-cmp v0.7.0 // indirect
	github.com/google/gopacket v1.1.19 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/gorilla/websocket v1.5.3 // indirect
	github.com/hashicorp/yamux v0.1.2 // indirect
	github.com/huin/goupnp v1.3.0 // indirect
	github.com/jackpal/go-nat-pmp v1.0.2 // indirect
	github.com/jsimonetti/rtnetlink v1.4.1 // indirect
	github.com/juju/ratelimit v1.0.2 // indirect
	github.com/klauspost/compress v1.20.0 // indirect
	github.com/klauspost/cpuid/v2 v2.4.1 // indirect
	github.com/koron/go-ssdp v0.0.4 // indirect
	github.com/libdns/acmedns v0.5.0 // indirect
	github.com/libdns/alidns v1.0.6 // indirect
	github.com/libdns/cloudflare v0.2.2 // indirect
	github.com/libdns/libdns v1.1.1 // indirect
	github.com/libp2p/go-nat v1.0.1-0.20250821073202-01afc089f138 // indirect
	github.com/libp2p/go-netroute v0.2.1 // indirect
	github.com/logrusorgru/aurora v2.0.3+incompatible // indirect
	github.com/mdlayher/netlink v1.11.2 // indirect
	github.com/mdlayher/socket v0.6.0 // indirect
	github.com/metacubex/utls v1.8.7 // indirect
	github.com/mholt/acmez/v3 v3.1.6 // indirect
	github.com/miekg/dns v1.1.73 // indirect
	github.com/pelletier/go-toml v1.9.5 // indirect
	github.com/pion/dtls/v3 v3.1.5 // indirect
	github.com/pion/logging v0.2.4 // indirect
	github.com/pion/stun/v3 v3.1.7 // indirect
	github.com/pion/transport/v4 v4.1.0 // indirect
	github.com/pires/go-proxyproto v0.16.0 // indirect
	github.com/quic-go/qpack v0.6.0 // indirect
	github.com/refraction-networking/utls v1.8.3-0.20260301010127-aa6edf4b11af // indirect
	github.com/robfig/cron/v3 v3.0.1 // indirect
	github.com/rogpeppe/go-internal v1.16.0 // indirect
	github.com/sagernet/bbolt v0.0.0-20260915102804-500ee1e84832 // indirect
	github.com/sagernet/fswatch v0.1.2 // indirect
	github.com/sagernet/gvisor v0.0.0-20260727.0-sing-box-mod.1 // indirect
	github.com/sagernet/netlink v0.0.0-20260814022025-64455d367bbf // indirect
	github.com/sagernet/nftables v0.3.0-mod.4 // indirect
	github.com/sagernet/quic-go v0.61.0-sing-box-mod.12 // indirect
	github.com/sagernet/sing v0.9.7-0.20261023115459-5dc452e537bf // indirect
	github.com/sagernet/sing-mux v0.3.10-0.20260929204512-caf09fe32475 // indirect
	github.com/sagernet/sing-quic v0.7.2-0.20261020082049-7e0a5869a5f4 // indirect
	github.com/sagernet/sing-shadowsocks v0.2.9-0.20260929204512-65740e0f0e3e // indirect
	github.com/sagernet/sing-shadowsocks2 v0.2.2-0.20260929152114-a69d1086332b // indirect
	github.com/sagernet/sing-snell v0.0.0-20260904135315-bc5a12ac736f // indirect
	github.com/sagernet/sing-tun v0.9.7-0.20261023115432-040db71fcd33 // indirect
	github.com/sagernet/sing-usbip v0.0.0-20260817040617-28bd42667eca // indirect
	github.com/sagernet/sing-vmess v0.2.9-0.20261019223527-a0c58542bd9d // indirect
	github.com/sagernet/smux v1.5.50-sing-box-mod.1 // indirect
	github.com/sagernet/ws v0.0.0-20231204124109-acfe8907c854 // indirect
	github.com/vishvananda/netlink v1.3.1 // indirect
	github.com/vishvananda/netns v0.0.5 // indirect
	github.com/wlynxg/anet v0.0.5 // indirect
	github.com/xtls/reality v0.0.0-20261014101318-83f621788ca8 // indirect
	github.com/yuin/gopher-lua v1.1.2 // indirect
	github.com/zeebo/blake3 v0.2.4 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.27.1 // indirect
	go.uber.org/zap/exp v0.3.0 // indirect
	go4.org/netipx v0.0.0-20231129151722-fdeea329fbba // indirect
	golang.org/x/crypto v0.58.0 // indirect
	golang.org/x/crypto/x509roots/fallback v0.0.0-20261020153306-9f2b28d4331a // indirect
	golang.org/x/exp v0.0.0-20260410095643-746e56fc9e2f // indirect
	golang.org/x/mod v0.41.0 // indirect
	golang.org/x/net v0.61.0 // indirect
	golang.org/x/sync v0.24.0 // indirect
	golang.org/x/sys v0.49.0 // indirect
	golang.org/x/text v0.43.0 // indirect
	golang.org/x/time v0.15.0 // indirect
	golang.zx2c4.com/wintun v0.0.0-20230126152724-0fa3db229ce2 // indirect
	golang.zx2c4.com/wireguard v0.0.0-20250521234502-f333402bd9cb // indirect
	golang.zx2c4.com/wireguard/windows v1.1.1 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260706201446-f0a921348800 // indirect
	google.golang.org/grpc v1.84.0 // indirect
	google.golang.org/protobuf v1.36.11 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	layeh.com/gopher-luar v1.0.11 // indirect
	lukechampine.com/blake3 v1.4.1 // indirect
)
