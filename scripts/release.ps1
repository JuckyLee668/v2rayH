<#
.SYNOPSIS
    打一个带可安装 .hap 的 GitHub Release（ClashBox 风格）。

.DESCRIPTION
    HAP 只能在本地构建：鸿蒙 SDK 随 DevEco Studio 分发，GitHub 的 Linux runner 上
    没有，所以 app 包无法在 CI 里产出。（libxray.a 是 CI 建的，本脚本直接复用
    entry/src/main/cpp/thirdparty/libxray/ 里已有的那份。）

    默认发布 **unsigned** HAP —— 签名材料是你机器上的调试证书，只对自己的设备有效，
    对别人无用；社区惯例（ClashBox 同样）是发未签名包，使用者用自己的证书自行签名。

.EXAMPLE
    .\scripts\release.ps1
    .\scripts\release.ps1 -Version 1.0.1
    .\scripts\release.ps1 -SkipBuild -Draft
    .\scripts\release.ps1 -SkipBuild -DryRun
#>
param(
    [string]$Version,
    [switch]$SkipBuild,
    [switch]$IncludeSigned,
    [switch]$Draft,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Info($m) { Write-Host "[release] $m" }
function Fail($m) { Write-Host "error: $m" -ForegroundColor Red; exit 1 }

# ---- version ---------------------------------------------------------------
if (-not $Version) {
    $app = Get-Content "AppScope/app.json5" -Raw
    if ($app -match '"versionName"\s*:\s*"([^"]+)"') {
        $Version = $Matches[1]
    } else {
        Fail "AppScope/app.json5 里读不到 versionName，请用 -Version 指定"
    }
}
$Tag = "v$Version"
Info "version = $Version    tag = $Tag"

# ---- 前置检查 --------------------------------------------------------------
$dirty = git status --porcelain
if ($dirty) { Fail "工作区不干净，先提交或 stash：`n$dirty" }

$branch = git rev-parse --abbrev-ref HEAD
if ($branch -ne "main") { Info "警告：当前分支是 $branch（不是 main）" }

if (git rev-parse -q --verify "refs/tags/$Tag" > $null) { Fail "tag $Tag 已存在" }

# ---- 构建 ------------------------------------------------------------------
if (-not $SkipBuild -and -not $DryRun) {
    Info "devecocli build ..."
    devecocli build
    if ($LASTEXITCODE -ne 0) { Fail "build 失败" }
}

$outDir = "entry/build/default/outputs/default"
$unsigned = Join-Path $outDir "entry-default-unsigned.hap"
$signed = Join-Path $outDir "entry-default-signed.hap"

if (-not (Test-Path -LiteralPath $unsigned)) { Fail "找不到 $unsigned（先跑一次构建）" }

# ---- 暂存产物 --------------------------------------------------------------
$dist = Join-Path $RepoRoot "dist"
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$assets = @()
$target = Join-Path $dist "v2rayH-$Version-unsigned.hap"
Copy-Item -LiteralPath $unsigned -Destination $target -Force
$assets += $target
Info ("unsigned -> " + (Split-Path -Leaf $target) + "  " + [math]::Round((Get-Item -LiteralPath $target).Length/1MB,2) + " MB")

if ($IncludeSigned) {
    if (Test-Path -LiteralPath $signed) {
        $s2 = Join-Path $dist "v2rayH-$Version-signed.hap"
        Copy-Item -LiteralPath $signed -Destination $s2 -Force
        $assets += $s2
        Info ("signed   -> " + (Split-Path -Leaf $s2))
    } else {
        Info "警告：要 signed 包但没找到 $signed"
    }
}

# ---- 校验和 ----------------------------------------------------------------
$shaFile = Join-Path $dist "v2rayH-$Version.sha256"
$lines = foreach ($a in $assets) {
    $h = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash.ToLower()
    "$h  " + (Split-Path -Leaf $a)
}
Set-Content -LiteralPath $shaFile -Value $lines -Encoding ASCII
$assets += $shaFile
Info ("sha256   -> " + (Split-Path -Leaf $shaFile))

# ---- release notes ---------------------------------------------------------
$notesFile = Join-Path $RepoRoot "docs/release-notes/$Version.md"
if (Test-Path -LiteralPath $notesFile) {
    $notes = Get-Content -LiteralPath $notesFile -Raw
    Info "notes 取自 docs/release-notes/$Version.md"
} else {
    $prev = (git tag --sort=-creatordate | Where-Object { $_ -ne $Tag } | Select-Object -First 1)
    $range = if ($prev) { "$prev..HEAD" } else { "HEAD" }
    $log = (git log $range --pretty=format:"- %s" --no-merges) -join "`n"
    if (-not $log) { $log = "- 首个发布" }
    $notes = @"
## 安装

1. 用你自己的证书给 ``v2rayH-$Version-unsigned.hap`` 签名（未签名包无法直接安装）。
2. ``hdc install`` 或设备助手安装。
3. 首次连接需要在系统弹窗里授予 VPN 权限。

## 变更

$log
"@
    Info "notes 由 git log 自动生成（范围 $range）"
}

# ---- 发布 ------------------------------------------------------------------
$ghArgs = @(
    "release", "create", $Tag,
    "--title", "v2rayH $Version",
    "--notes", $notes
)
if ($Draft) { $ghArgs += "--draft" }
$ghArgs += $assets

if ($DryRun) {
    Info "DRY RUN，未发布。等价命令："
    Write-Host ("gh " + ($ghArgs[0..5] -join " ") + " ... ")
    Write-Host "  产物："
    $assets | ForEach-Object { Write-Host "    $_" }
    exit 0
}

Info "gh release create $Tag ..."
& gh @ghArgs
if ($LASTEXITCODE -ne 0) { Fail "gh release create 失败" }

Info "完成：$(git remote get-url origin)  ->  Releases / $Tag"
