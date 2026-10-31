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
	"sync/atomic"
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
func MeasureDelay(configJSON *C.char, singboxJSON *C.char, testURL *C.char) C.longlong {
	cfg := C.GoString(configJSON)
	sbCfg := C.GoString(singboxJSON)
	urlStr := C.GoString(testURL)
	if sbCfg != "" {
		sbInst, err := startSingboxInstance(sbCfg)
		if err != nil {
			vpnLog("measure delay sing-box start failed: " + err.Error())
			return C.longlong(-1)
		}
		defer sbInst.Close()
	}
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
func MeasureDownload(configJSON *C.char, singboxJSON *C.char, testURL *C.char, maxBytes C.longlong) C.double {
	cfg := C.GoString(configJSON)
	sbCfg := C.GoString(singboxJSON)
	urlStr := C.GoString(testURL)
	limit := int64(maxBytes)
	if limit <= 0 {
		limit = 40 * 1024 * 1024
	}
	if sbCfg != "" {
		sbInst, err := startSingboxInstance(sbCfg)
		if err != nil {
			vpnLog("measure download sing-box start failed: " + err.Error())
			return C.double(-1)
		}
		defer sbInst.Close()
	}
	inst, err := core.StartInstance("json", []byte(cfg))
	if err != nil {
		vpnLog("measure download start failed: " + err.Error())
		return C.double(-1)
	}
	defer inst.Close()

	// Speedtest-style measurement: several parallel downloads, an untimed
	// warmup phase that gets past TCP slow start and connection setup, then
	// the sustained rate of what follows. Measuring from the first byte of a
	// single cold connection reports only a fraction of the real throughput.
	const (
		workers         = 4
		warmupTarget    = 16 << 20 // 16MiB untimed
		warmupMaxWait   = 5 * time.Second
		timedMaxWait    = 20 * time.Second
		minTimedBytes   = 256 << 10
		requestTimeout  = 45 * time.Second
		readBufSize     = 128 * 1024
		monitorInterval = 10 * time.Millisecond
	)

	warmup := limit / 5
	if warmup > warmupTarget {
		warmup = warmupTarget
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stopOnce := sync.Once{}
	stopAll := func() {
		stopOnce.Do(func() { cancel() })
	}

	var (
		total     atomic.Int64
		active    atomic.Int32
		firstByte time.Time
	)

	var wg sync.WaitGroup
	active.Store(workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			defer active.Add(-1)
			transport := &http.Transport{
				DisableCompression: true,
				DialContext: func(dctx context.Context, network string, addr string) (net.Conn, error) {
					dest, derr := xnet.ParseDestination(network + ":" + addr)
					if derr != nil {
						return nil, derr
					}
					return core.Dial(dctx, inst, dest)
				},
			}
			client := &http.Client{Transport: transport}
			reqCtx, cancelReq := context.WithTimeout(ctx, requestTimeout)
			defer cancelReq()
			req, rerr := http.NewRequestWithContext(reqCtx, http.MethodGet, urlStr, nil)
			if rerr != nil {
				return
			}
			resp, err := client.Do(req)
			if err != nil {
				if ctx.Err() == nil {
					vpnLog("measure download request failed: " + err.Error())
				}
				return
			}
			defer resp.Body.Close()
			if resp.StatusCode < 200 || resp.StatusCode >= 300 {
				vpnLog("measure download status: " + strconv.Itoa(resp.StatusCode))
				return
			}
			buf := make([]byte, readBufSize)
			for ctx.Err() == nil {
				n, rerr := resp.Body.Read(buf)
				if n > 0 {
					total.Add(int64(n))
					if total.Load() >= limit {
						stopAll()
						return
					}
				}
				if rerr != nil {
					return
				}
			}
		}()
	}

	start := time.Now()
	var timedStart time.Time
	var base int64
	tick := time.NewTicker(monitorInterval)
	defer tick.Stop()
	for {
		select {
		case <-tick.C:
			now := time.Now()
			cur := total.Load()
			if cur > 0 && firstByte.IsZero() {
				firstByte = now
			}
			if timedStart.IsZero() {
				if cur >= warmup || now.Sub(start) >= warmupMaxWait {
					timedStart = now
					base = cur
				}
			} else if cur >= limit || now.Sub(timedStart) >= timedMaxWait {
				goto done
			}
			if active.Load() == 0 {
				goto done
			}
		}
	}
done:
	stopAll()
	wg.Wait()

	cur := total.Load()
	if cur <= 0 {
		return C.double(-1)
	}
	if !timedStart.IsZero() {
		elapsed := time.Since(timedStart).Seconds()
		if cur-base >= minTimedBytes && elapsed > 0 {
			return C.double(float64(cur-base) / elapsed)
		}
	}
	if !firstByte.IsZero() {
		if elapsed := time.Since(firstByte).Seconds(); elapsed > 0 {
			return C.double(float64(cur) / elapsed)
		}
	}
	return C.double(-1)
}

func main() {}
