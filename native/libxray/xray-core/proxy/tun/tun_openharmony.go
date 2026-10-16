//go:build openharmony

package tun

import (
	"context"
	"strconv"

	"github.com/xtls/xray-core/common/errors"
	"github.com/xtls/xray-core/common/platform"
	"golang.org/x/sys/unix"
	"gvisor.dev/gvisor/pkg/tcpip/link/fdbased"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

type OpenHarmonyTun struct {
	tunFd   int
	options TunOptions
}

// OpenHarmonyTun implements Tun
var _ Tun = (*OpenHarmonyTun)(nil)

// OpenHarmonyTun implements GVisorTun
var _ GVisorTun = (*OpenHarmonyTun)(nil)

// NewTun builds new tun interface handler
func NewTun(options TunOptions) (Tun, error) {
	fd, err := strconv.Atoi(platform.NewEnvFlag(platform.TunFdKey).GetValue(func() string { return "0" }))
	errors.LogInfo(context.Background(), "read OpenHarmony Tun Fd ", fd, err)

	err = unix.SetNonblock(fd, true)
	if err != nil {
		_ = unix.Close(fd)
		return nil, err
	}

	return &OpenHarmonyTun{
		tunFd:   fd,
		options: options,
	}, nil
}

func (t *OpenHarmonyTun) Start() error {
	return nil
}

func (t *OpenHarmonyTun) Close() error {
	return nil
}

func (t *OpenHarmonyTun) newEndpoint() (stack.LinkEndpoint, error) {
	return fdbased.New(&fdbased.Options{
		FDs:               []int{t.tunFd},
		MTU:               t.options.MTU,
		RXChecksumOffload: true,
	})
}
