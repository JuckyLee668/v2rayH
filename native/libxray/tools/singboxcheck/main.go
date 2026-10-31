// singboxcheck is a host-side smoke test for the sing-box wiring used by
// libxray. It mirrors the registry set from libxray/singbox.go, starts a box
// from a config file, then probes the mixed inbound via an HTTP proxy request.
// It registers the exact same protocols as the app context so config parsing
// and outbound construction are validated identically.
//
// Usage: go run ./tools/singboxcheck <config.json> [probeURL]
package main

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter/certificate"
	"github.com/sagernet/sing-box/adapter/endpoint"
	"github.com/sagernet/sing-box/adapter/inbound"
	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/adapter/service"
	"github.com/sagernet/sing-box/dns"
	dnstransport "github.com/sagernet/sing-box/dns/transport"
	"github.com/sagernet/sing-box/dns/transport/local"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/protocol/block"
	"github.com/sagernet/sing-box/protocol/direct"
	"github.com/sagernet/sing-box/protocol/hysteria2"
	"github.com/sagernet/sing-box/protocol/mixed"
	"github.com/sagernet/sing-box/protocol/shadowsocks"
	"github.com/sagernet/sing-box/protocol/trojan"
	"github.com/sagernet/sing-box/protocol/tuic"
	"github.com/sagernet/sing-box/protocol/vless"
	"github.com/sagernet/sing-box/protocol/vmess"
)

// buildContext matches buildSingboxContext in libxray/singbox.go exactly.
func buildContext() context.Context {
	inReg := inbound.NewRegistry()
	mixed.RegisterInbound(inReg)
	direct.RegisterInbound(inReg)

	outReg := outbound.NewRegistry()
	direct.RegisterOutbound(outReg)
	block.RegisterOutbound(outReg)
	vless.RegisterOutbound(outReg)
	vmess.RegisterOutbound(outReg)
	trojan.RegisterOutbound(outReg)
	shadowsocks.RegisterOutbound(outReg)
	hysteria2.RegisterOutbound(outReg)
	tuic.RegisterOutbound(outReg)

	epReg := endpoint.NewRegistry()

	dnsReg := dns.NewTransportRegistry()
	dnstransport.RegisterTCP(dnsReg)
	dnstransport.RegisterUDP(dnsReg)
	local.RegisterTransport(dnsReg)

	svcReg := service.NewRegistry()
	certReg := certificate.NewRegistry()

	return box.Context(context.Background(), inReg, outReg, epReg, dnsReg, svcReg, certReg)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: singboxcheck <config.json> [probeURL] [proxyAddr]")
		os.Exit(2)
	}
	probeURL := "http://www.msftconnecttest.com/connecttest.txt"
	if len(os.Args) >= 3 {
		probeURL = os.Args[2]
	}
	proxyAddr := "127.0.0.1:10812"
	if len(os.Args) >= 4 {
		proxyAddr = os.Args[3]
	}

	content, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "read config:", err)
		os.Exit(1)
	}

	ctx := buildContext()
	var options option.Options
	err = options.UnmarshalJSONContext(ctx, content)
	if err != nil {
		fmt.Fprintln(os.Stderr, "parse config:", err)
		os.Exit(1)
	}
	fmt.Println("config parsed OK")

	instance, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, "box.New:", err)
		os.Exit(1)
	}
	fmt.Println("box created OK")

	err = instance.Start()
	if err != nil {
		fmt.Fprintln(os.Stderr, "box.Start:", err)
		instance.Close()
		os.Exit(1)
	}
	fmt.Println("box started OK")

	proxyURL, err := url.Parse("http://" + proxyAddr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "parse proxy:", err)
		instance.Close()
		os.Exit(1)
	}
	client := &http.Client{
		Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)},
		Timeout:   15 * time.Second,
	}
	start := time.Now()
	resp, err := client.Get(probeURL)
	if err != nil {
		fmt.Fprintln(os.Stderr, "probe via mixed inbound:", err)
		instance.Close()
		os.Exit(1)
	}
	resp.Body.Close()
	fmt.Printf("probe OK: status=%d elapsed=%dms\n", resp.StatusCode, time.Since(start).Milliseconds())

	instance.Close()
	fmt.Println("box closed OK")
	fmt.Println("SINGBOXCHECK PASS")
}
