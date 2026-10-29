# v2rayH

[v2rayNG](https://github.com/2dust/v2rayNG) 的 HarmonyOS / OpenHarmony 移植版：
一个 VLESS / VMess / Trojan / Shadowsocks 客户端，内置
[Xray-core](https://github.com/xtls/xray-core) 内核，通过系统 VPN 接口接管全部流量。

流量路径：

```
应用 ──► vpn-tun (VpnExtensionAbility) ──► gVisor 网络栈 (L3→L4)
      ──► Xray VLESS+REALITY 出站 ──► 互联网
```
![](intro.jpg)

## 功能特性

- VLESS / VMess / Trojan / Shadowsocks 协议支持（Xray 内核）
- 多订阅分组管理：每组独立链接、独立更新、独立节点列表
- 节点延迟测速 + 下载测速（走当前节点的临时 Xray 实例，不影响已建立的 VPN）
- 剪贴板一键导入节点链接（自动申请读取权限）
- 底部页签沉浸光感材质（HDS 组件，随设备算力自适应）
- 深色模式与主题色跟随系统

## 目录结构

| 路径 | 说明 |
| --- | --- |
| `entry/src/main/ets/` | ArkTS 界面、订阅解析、VPN 扩展 Ability |
| `entry/src/main/cpp/` | NAPI 模块（`libentry.so`），承载 Go 内核 |
| `native/libxray/` | Go 封装 + 内嵌并打过补丁的 `xray-core` 与 `gvisor` |
| `native/build_libxray.sh` | 重新构建 `libxray.a`（openharmony/arm64）— Linux/CI |
| `native/build_libxray.ps1` | 同上，Windows 版 |
| `.github/workflows/build-libxray.yml` | 产出 `libxray.a` 的 CI |

## 原生内核

内核以 **c-archive** 形式构建，由 CMake 静态链接进 `libentry.so`，
因此没有需要随包分发的运行时 SONAME。

构建需要两样东西：

1. **ohos-go** — 认识 `GOOS=openharmony` / `GOARCH=arm64` 的 Go 工具链，
   预编译包（`linux-amd64` / `darwin-arm64`）来自
   <https://github.com/sysit/ohos-go/releases>。
   （官方 Go 无法交叉编译 OpenHarmony；且官方编译器会生成
   `R_AARCH64_TLS_TPREL64` initial-exec TLS 重定位，musl 在 `dlopen`
   时会拒绝加载，ohos-go 生成的是 `R_AARCH64_TLSDESC`。）
2. **OpenHarmony SDK 原生工具链** — 面向 `aarch64-linux-ohos` 的
   `clang` + `sysroot`。可从 DevEco Studio
   （`sdk/default/openharmony/native/…`）或公开镜像
   <https://repo.huaweicloud.com/openharmony/os/> 获取，
   `ohos-sdk-windows_linux-public.tar.gz` 内含按组件拆分的
   `linux/native-*.zip`。

```bash
# Linux / CI
OHOS_GO=/path/to/ohos-go OHOS_SDK=/path/to/ohos-sdk ./native/build_libxray.sh

# Windows
.\native\build_libxray.ps1 -OHOS_GO C:\ohos-go -OHOS_SDK "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony"
```

两者都会把产物复制到 `entry/src/main/cpp/thirdparty/libxray/`
（`libs/arm64-v8a/libxray.a` + `include/libxray.h`），该目录被 git 忽略 ——
但 `devecocli build` 需要它存在。

## 构建应用

```bash
devecocli build
devecocli run --skip-build
```

`build-profile.json5` 中 `compatibleSdkVersion` 为 `6.1.0(23)`，
即 HAP 可安装在 HarmonyOS 6.1 及以上；编译使用本机安装的 API 26 SDK。

## CI

共两个工作流：

- `.github/workflows/build-libxray.yml` — 构建 Xray 内核（`libxray.a`）
  并作为附件挂到 Release。
- `.github/workflows/build-hap.yml` — 在 `ubuntu-22.04` 上用 `devecocli`
  构建**未签名 HAP**，在 Release 发布时（或手动触发时）发布产物。

### 没有 DevEco Studio 时 HAP 怎么构建

华为 Linux 版 **Command Line Tools**（CLT）内嵌 HarmonyOS SDK，
`devecocli` 在 `DEVECO_CLI_CLT_PATH` 指向解压后的 CLT 时官方支持 Linux。
这取代了早先「OpenHarmony SDK + hvigor 授权绕过」的方案。

一次性引导（CLT 压缩包在华为下载门户后面）：

1. 从 <https://developer.huawei.com/consumer/cn/download/> 下载
   `commandline-tools-linux-x64-26.0.0.zip`。
2. 若压缩包小于 GitHub 单文件 2 GB 限制：创建一个标签为 `clt` 的
   Release 并上传；或把 `CLT_ARCHIVE_URL` 设为直链。
   若超过 2 GB：分卷后上传到 `clt` Release，工作流会自动合并：

   ```bash
   split -b 1900M -d -a 2 commandline-tools-linux-x64-26.0.0.zip \
     commandline-tools-linux-x64-26.0.0.zip.part
   gh release create clt commandline-tools-linux-x64-26.0.0.zip.part*
   # Release 已存在时：
   gh release upload clt commandline-tools-linux-x64-26.0.0.zip.part* --clobber
   ```

   Windows 上可在 Git Bash 里执行 `split`，或用 7-Zip 的「切分卷」
   （1900M），得到 `.zip.001`、`.zip.002`… —— 两种命名工作流都能合并。

   > GitHub **网页上传**会拒绝 `.part00` / `.001`（提示 “We don't support
   > that file type.”）。该限制只存在于网页端；`gh release upload` 接受
   > 任意文件名。如必须用网页端，给每个分卷追加 `.zip` 后缀即可
   > （文件内容不变）：
   >
   > ```bash
   > for f in commandline-tools-linux-x64-26.0.0.zip.part*; do mv "$f" "$f.zip"; done
   > # 7-Zip 分卷：for f in *.zip.[0-9][0-9][0-9]; do mv "$f" "$f.zip"; done
   > ```
   >
   > 然后上传 `*.part*.zip` / `*.zip.NNN.zip`，工作流按文件名顺序拼接。
   >
   > `CLT_ARCHIVE_URL` 也可指向托管在支持大文件平台
   > （S3/R2/OSS 等）上的单个压缩包。
3. 运行 `build-hap`。工作流会缓存解压后的 CLT 和 `libxray.a`，
   之后的运行只重新构建应用。

`libxray.a` 被 git 忽略。缓存未命中时工作流会用 `ohos-go` 从源码构建，
因此 `native/` 下的改动总会被包含。也可设置 `libxray_tag` 复用某个
已知可用的 `libxray.a` / `libxray.h` Release 附件（更快，但原生代码
变化后必须重新构建）。

> 自托管 runner 装 DevEco Studio 也可以：设置 `DEVECO_CLI_STUDIO_PATH`
> 后执行 `devecocli build`。仓库内的工作流走的是托管 Linux + CLT 路线。

## 发布

Release 附带可安装的**未签名 `.hap`** —— 与 ClashBox 惯例一致：
签名绑定开发者证书和设备，对他人无用，社区只发未签名包。

`build-hap.yml` 在 CI 中产出未签名 HAP。发布 GitHub Release（或以
`publish: true` 手动触发工作流）后，`v2rayH-<版本>-unsigned.hap` 与
`v2rayH-<版本>.sha256` 会自动挂到 Release 上。

本地发布同样可用：

```powershell
.\scripts\release.ps1                  # 版本号取自 AppScope/app.json5
.\scripts\release.ps1 -Version 0.2.2
.\scripts\release.ps1 -SkipBuild -Draft
.\scripts\release.ps1 -SkipBuild -DryRun
```

脚本会构建、暂存 `dist/v2rayH-<版本>-unsigned.hap` 与 `.sha256`，
然后打 tag 并创建 Release。若存在手写的 `docs/release-notes/<版本>.md`
则用 `--notes-file`，否则用 GitHub 自动生成的 `--generate-notes`。

### 签名

`build-profile.json5` 有意**不携带** `signingConfigs`：里面是机器相关的
路径和加密口令。新克隆的仓库因此构建出的是未签名 HAP —— 这正是发布物。

要在自己的设备上安装仍需签名 —— 让 DevEco Studio 自动生成
（Project Structure → Signing Configs → Automatically generate signature），
然后用 skip-worktree 把本地改动隔离掉：

```bash
git update-index --skip-worktree build-profile.json5
```

## OpenHarmony 补丁

`native/libxray/go.mod` 通过 `replace` 把 `github.com/xtls/xray-core`
和 `gvisor.dev/gvisor` 重定向到仓库内嵌副本。三组 overlay 让它们能在
OpenHarmony 上构建运行 —— 见 `native/README.md`。

构建与运行过程中踩过的完整坑位清单（initial-exec TLS 与 musl 的冲突、
cgo `CC` 包装器、gVisor 的 `fstat` 拒绝、路由回环、CI 打包陷阱等），
见 [`docs/build-notes.md`](docs/build-notes.md)。
