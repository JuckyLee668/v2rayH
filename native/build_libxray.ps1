# build_libxray.ps1
# 一键重编 Xray 内核 (libxray.a) 并拷贝到工程 cpp/thirdparty 目录。
#
# 前置：
#   - ohos-go 补丁工具链 (默认 C:\ohos-go)
#   - HarmonyOS SDK (默认 DevEco Studio 自带)
#   - 本机 Go (用于构建 ccwrap.exe)
#
# 用法: .\build_libxray.ps1 [-OHOS_GO path] [-OHOS_SDK path] [-STOCK_GO path]

param(
    [string]$OHOS_GO = "C:\ohos-go",
    [string]$OHOS_SDK = "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony",
    [string]$STOCK_GO = "C:\Program Files\Go\bin\go.exe"
)

$ErrorActionPreference = "Stop"

$NativeDir = $PSScriptRoot
$LibDir = Join-Path $NativeDir "libxray"
$ToolsDir = Join-Path $NativeDir "tools"
$CcwrapDir = Join-Path $ToolsDir "ccwrap"
$CcwrapExe = Join-Path $ToolsDir "ccwrap.exe"
$ArExe = Join-Path $ToolsDir "ar.exe"

$OhosGo = Join-Path $OHOS_GO "bin\go.exe"
$LlvmAr = Join-Path $OHOS_SDK "native\llvm\bin\llvm-ar.exe"

if (-not (Test-Path $OhosGo)) { throw "未找到 ohos-go 工具链: $OhosGo" }
if (-not (Test-Path $LlvmAr)) { throw "未找到 llvm-ar: $LlvmAr" }

# 1. 构建 ccwrap.exe (宿主工具)
if (-not (Test-Path $CcwrapExe)) {
    Write-Host "[1/4] 构建 ccwrap.exe ..."
    & $STOCK_GO build -o $CcwrapExe (Join-Path $CcwrapDir "ccwrap.go")
    if ($LASTEXITCODE -ne 0) { throw "ccwrap.exe 构建失败" }
}

# 2. 准备 ar.exe (llvm-ar)
if (-not (Test-Path $ArExe)) {
    Write-Host "[2/4] 复制 llvm-ar 为 ar.exe ..."
    Copy-Item $LlvmAr $ArExe -Force
}

# 3. 交叉编译 libxray.a
# with_utls: sing-box 的 reality/utls 实现被该 build tag 门控，缺失会导致
#            "uTLS, which is required by reality is not included in this build"
Write-Host "[3/4] 交叉编译 libxray.a (openharmony/arm64, c-archive, with_utls) ..."
$env:OHOS_SDK = $OHOS_SDK
$env:GOOS = "openharmony"
$env:GOARCH = "arm64"
$env:CGO_ENABLED = "1"
$env:CC = $CcwrapExe
$env:CGO_CFLAGS = ""
$env:CGO_LDFLAGS = ""
$env:PATH = "$ToolsDir;$env:PATH"

Push-Location $LibDir
try {
    & $OhosGo build -tags with_utls -buildmode=c-archive -o "libxray.a" .
    if ($LASTEXITCODE -ne 0) { throw "go build 失败" }
}
finally {
    Pop-Location
}

# 4. 拷贝到工程
Write-Host "[4/4] 拷贝 libxray.a + libxray.h 到工程 ..."
$CppThird = [System.IO.Path]::GetFullPath((Join-Path $NativeDir "..\entry\src\main\cpp\thirdparty\libxray"))
Copy-Item (Join-Path $LibDir "libxray.a") (Join-Path $CppThird "libs\arm64-v8a\libxray.a") -Force
Copy-Item (Join-Path $LibDir "libxray.h") (Join-Path $CppThird "include\libxray.h") -Force

Write-Host "完成 -> $CppThird"
