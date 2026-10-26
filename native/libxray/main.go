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

//export MeasureDownload
func MeasureDownload(configJSON *C.char, testURL *C.char, maxBytes C.longlong) C.double {
	cfg := C.GoString(configJSON)
	urlStr := C.GoString(testURL)
	limit := int64(maxBytes)
	if limit <= 0 {
		limit = 20 * 1024 * 1024
	}
	inst, err := core.StartInstance("json", []byte(cfg))
	if err != nil {
		vpnLog("measure download start failed: " + err.Error())
		return C.double(-1)
	}
	defer inst.Close()

	transport := &http.Transport{
		DisableCompression: true,
		DialContext: func(ctx context.Context, network string, addr string) (net.Conn, error) {
			dest, derr := xnet.ParseDestination(network + ":" + addr)
			if derr != nil {
				return nil, derr
			}
			return core.Dial(ctx, inst, dest)
		},
	}
	client := &http.Client{Transport: transport, Timeout: 25 * time.Second}
	resp, err := client.Get(urlStr)
	if err != nil {
		vpnLog("measure download request failed: " + err.Error())
		return C.double(-1)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		vpnLog("measure download status: " + strconv.Itoa(resp.StatusCode))
		return C.double(-1)
	}

	buf := make([]byte, 32*1024)
	var total int64
	start := time.Now()
	for total < limit {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			total += int64(n)
		}
		if rerr != nil {
			break
		}
	}
	elapsed := time.Since(start).Seconds()
	if total <= 0 || elapsed <= 0 {
		return C.double(-1)
	}
	return C.double(float64(total) / elapsed)
}

func main() {}
