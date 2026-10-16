package main

/*
#cgo LDFLAGS: -lhilog_ndk.z
#include <stdlib.h>
#include <stdint.h>
#include <hilog/log.h>

static void xlog_info(const char* tag, const char* msg) {
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, 0x0000, tag, msg);
}
*/
import "C"

import (
	"context"
	"net"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
	"unsafe"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all"
)

var (
	mu        sync.Mutex
	instance  *core.Instance
	lastError string
)

func vpnLog(msg string) {
	ctag := C.CString("v2rayH")
	cmsg := C.CString(msg)
	C.xlog_info(ctag, cmsg)
	C.free(unsafe.Pointer(ctag))
	C.free(unsafe.Pointer(cmsg))
}

//export StartXray
func StartXray(configJSON *C.char) C.int {
	cfg := C.GoString(configJSON)
	inst, err := core.StartInstance("json", []byte(cfg))
	if err != nil {
		mu.Lock()
		lastError = err.Error()
		mu.Unlock()
		return C.int(1)
	}
	mu.Lock()
	instance = inst
	lastError = ""
	mu.Unlock()
	return C.int(0)
}

//export GetLastError
func GetLastError() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return C.CString(lastError)
}

//export StopXray
func StopXray() C.int {
	mu.Lock()
	inst := instance
	instance = nil
	mu.Unlock()
	if inst != nil {
		inst.Close()
	}
	return C.int(0)
}

//export IsXrayRunning
func IsXrayRunning() C.int {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil && instance.IsRunning() {
		return C.int(1)
	}
	return C.int(0)
}

//export StartVpnTun
func StartVpnTun(fd C.int, configJSON *C.char, assetDir *C.char) C.int {
	assets := C.GoString(assetDir)
	if len(assets) > 0 {
		os.Setenv("xray.location.asset", assets)
	}
	os.Setenv("xray.tun.fd", strconv.Itoa(int(fd)))
	cfg := C.GoString(configJSON)
	inst, err := core.StartInstance("json", []byte(cfg))
	if err != nil {
		mu.Lock()
		lastError = err.Error()
		mu.Unlock()
		vpnLog("start vpn tun failed: " + err.Error())
		return C.int(1)
	}
	mu.Lock()
	instance = inst
	lastError = ""
	mu.Unlock()
	vpnLog("vpn tun started")
	return C.int(0)
}

//export StopVpn
func StopVpn() C.int {
	return StopXray()
}

//export MeasureDelay
func MeasureDelay(configJSON *C.char, testURL *C.char) C.longlong {
	cfg := C.GoString(configJSON)
	urlStr := C.GoString(testURL)
	inst, err := core.StartInstance("json", []byte(cfg))
	if err != nil {
		vpnLog("measure delay start failed: " + err.Error())
		return C.longlong(-1)
	}
	defer inst.Close()

	transport := &http.Transport{
		DialContext: func(ctx context.Context, network string, addr string) (net.Conn, error) {
			dest, derr := xnet.ParseDestination(network + ":" + addr)
			if derr != nil {
				return nil, derr
			}
			return core.Dial(ctx, inst, dest)
		},
	}
	client := &http.Client{Transport: transport, Timeout: 10 * time.Second}
	start := time.Now()
	resp, err := client.Get(urlStr)
	if err != nil {
		vpnLog("measure delay request failed: " + err.Error())
		return C.longlong(-1)
	}
	resp.Body.Close()
	return C.longlong(time.Since(start).Milliseconds())
}

func main() {}
