package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

func main() {
	sdk := os.Getenv("OHOS_SDK")
	if sdk == "" {
		if runtime.GOOS == "windows" {
			sdk = "C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony"
		} else {
			sdk = "/opt/ohos-sdk"
		}
	}
	clangName := "clang"
	if runtime.GOOS == "windows" {
		clangName = "clang.exe"
	}
	clang := filepath.Join(sdk, "native", "llvm", "bin", clangName)
	sysroot := filepath.Join(sdk, "native", "sysroot")
	args := []string{"-target", "aarch64-linux-ohos", "--sysroot=" + sysroot, "-D__MUSL__"}
	args = append(args, os.Args[1:]...)
	cmd := exec.Command(clang, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			os.Exit(ee.ExitCode())
		}
		os.Exit(1)
	}
}
