//go:build openharmony

package tun

import (
	"context"
	"net"
	"strconv"

	"github.com/xtls/xray-core/common/errors"
	"github.com/xtls/xray-core/common/platform"
	"golang.org/x/sys/unix"
)

// OpenHarmonyTun is an object that handles the tun file descriptor handed over
// by VpnExtensionAbility. The descriptor stays with the application, Close ends
// the reading of a duplicate.
type OpenHarmonyTun struct {
	*fdTun
	options *Config
}

// OpenHarmonyTun implements Tun
var _ Tun = (*OpenHarmonyTun)(nil)

// NewTun builds new tun interface handler
func NewTun(options *Config) (Tun, error) {
	fd, err := strconv.Atoi(platform.NewEnvFlag(platform.TunFdKey).GetValue(func() string { return "0" }))
	errors.LogInfo(context.Background(), "read OpenHarmony Tun Fd ", fd, err)

	err = unix.SetNonblock(fd, true)
	if err != nil {
		_ = unix.Close(fd)
		return nil, err
	}

	// the descriptor stays with the application, Close ends the reading of a duplicate
	fd, err = unix.FcntlInt(uintptr(fd), unix.F_DUPFD_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}

	return &OpenHarmonyTun{
		fdTun:   newFdTun(fd, 0),
		options: options,
	}, nil
}

func (t *OpenHarmonyTun) Start() error {
	return nil
}

func (t *OpenHarmonyTun) Close() error {
	return t.closeFile()
}

func (t *OpenHarmonyTun) Name() (string, error) {
	ifr, err := unix.NewIfreq("")
	if err != nil {
		return "", err
	}
	if err = unix.IoctlIfreq(t.fd, unix.TUNGETIFF, ifr); err != nil {
		return "", err
	}
	return ifr.Name(), nil
}

func (t *OpenHarmonyTun) Index() (int, error) {
	name, err := t.Name()
	if err != nil {
		return 0, err
	}
	iface, err := net.InterfaceByName(name)
	if err != nil {
		return 0, err
	}
	return iface.Index, nil
}

func setinterface(network, address string, fd uintptr, iface *net.Interface) error {
	return unix.BindToDevice(int(fd), iface.Name)
}

func findOutboundInterface(tunIndex int, fixedName string) (*net.Interface, error) {
	if fixedName == "" {
		return nil, errors.New("automatic outbound interface selection is not supported on this platform")
	}
	iface, err := net.InterfaceByName(fixedName)
	if err != nil {
		return nil, err
	}
	if iface.Index == tunIndex {
		return nil, errors.New("outbound interface cannot be the TUN interface")
	}
	return iface, nil
}
