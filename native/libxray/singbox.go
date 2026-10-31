package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"sync"

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

const singboxVersion = "sing-box v1.14.4"

var (
	sbMu        sync.Mutex
	sbInstance  *box.Box
	sbLastError string
)

// buildSingboxContext registers only the protocols we actually ship:
// mixed/direct inbounds and direct/block/vless/vmess/trojan/shadowsocks/
// hysteria2/tuic outbounds plus local/tcp/udp DNS transports. This avoids
// pulling tun/gvisor/wireguard via the include package.
func buildSingboxContext() context.Context {
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

func startSingboxInstance(configJSON string) (*box.Box, error) {
	ctx := buildSingboxContext()
	var options option.Options
	err := options.UnmarshalJSONContext(ctx, []byte(configJSON))
	if err != nil {
		return nil, err
	}
	instance, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		return nil, err
	}
	err = instance.Start()
	if err != nil {
		instance.Close()
		return nil, err
	}
	return instance, nil
}

//export StartSingbox
func StartSingbox(configJSON *C.char) C.int {
	cfg := C.GoString(configJSON)
	sbMu.Lock()
	defer sbMu.Unlock()
	if sbInstance != nil {
		sbLastError = "sing-box already running"
		return C.int(2)
	}
	inst, err := startSingboxInstance(cfg)
	if err != nil {
		sbLastError = err.Error()
		vpnLog("start sing-box failed: " + err.Error())
		return C.int(1)
	}
	sbInstance = inst
	sbLastError = ""
	vpnLog("sing-box started")
	return C.int(0)
}

//export StopSingbox
func StopSingbox() C.int {
	sbMu.Lock()
	defer sbMu.Unlock()
	inst := sbInstance
	sbInstance = nil
	if inst != nil {
		inst.Close()
		vpnLog("sing-box stopped")
	}
	return C.int(0)
}

//export IsSingboxRunning
func IsSingboxRunning() C.int {
	sbMu.Lock()
	defer sbMu.Unlock()
	if sbInstance != nil {
		return C.int(1)
	}
	return C.int(0)
}

//export GetSingboxVersion
func GetSingboxVersion() *C.char {
	return C.CString(singboxVersion)
}

//export GetSingboxError
func GetSingboxError() *C.char {
	sbMu.Lock()
	defer sbMu.Unlock()
	return C.CString(sbLastError)
}
