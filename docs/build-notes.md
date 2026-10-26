# 编译问题与修复记录

把 Xray 内核搬到 OpenHarmony 上一路踩到的坑。按「工具链 → 依赖补丁 → 运行期 → CI」排序，
每条尽量写清**现象 / 原因 / 改法**。

---

## 1. 原生 Go 根本编不出 openharmony

**现象** `GOOS=openharmony GOARCH=arm64 go build` 直接报不支持的平台组合。

**原因** 上游 Go 没有 `openharmony` 这个 GOOS。

**改法** 换 [ohos-go](https://github.com/sysit/ohos-go)——加了 OpenHarmony 支持的 Go fork，
提供 linux-amd64 / darwin-arm64 预编译包，解包即用。它有个关键设计：在 `openharmony` 下
`runtime.GOOS` **仍然是 `"linux"`**，靠 `runtime.IsOpenharmony` 区分。这就是第 6 节补丁的根源。

---

## 2. TLS 模型：最隐蔽的一个

**现象** 编译、链接全过，装到设备上 `dlopen` 失败：

```
initial-exec TLS resolves to dynamic definition
```

**原因** 原生 Go 给 arm64 生成 initial-exec 模型的 TLS 重定位（`R_AARCH64_TLS_TPREL64`）。
OpenHarmony 用 musl，动态库里出现 initial-exec 定义会被直接拒绝。ohos-go 改成生成
`R_AARCH64_TLSDESC`（GD 模型），musl 才接受。

**改法** 用 ohos-go，别想着用原生 Go 去调 TLS 标志。注意这个坑**编译期完全看不出来**，
所以「编译通过」不等于没事。

---

## 3. cgo：CC 要带绝对路径 + target + sysroot

**原因** `CC` 只写 `clang` 会解析到错误的 clang；而且目标三元组和 sysroot 必须显式传给 SDK 自带的那个。

**改法** 写了个二十来行的包装器 `native/tools/ccwrap/ccwrap.go`，补全参数后转发：

```
clang -target aarch64-linux-ohos --sysroot=<SDK>/native/sysroot -D__MUSL__ ...
```

`-D__MUSL__` 不能省，否则会选到 glibc 分支。SDK 根目录走 `OHOS_SDK` 环境变量，
包装器本身跨平台（Windows 下自动用 `clang.exe`）。Windows 上另外用目录 junction
归一化了 SDK 路径。

---

## 4. `ar` 必须指向 llvm-ar

c-archive 的归档阶段需要 PATH 上有 `ar`。统一用 SDK 自带的 llvm-ar，不用 GNU ar：

```bash
ln -sf "$OHOS_SDK/native/llvm/bin/llvm-ar" "$TOOLS_DIR/bin/ar"
```

---

## 5. 链接方式：c-archive，不是 c-shared

原本考虑 `-buildmode=c-shared` 出 `.so` 塞进 HAP，但 SONAME / 依赖解析在 HAP 里不省心。
最终改成 `-buildmode=c-archive` 出静态库，由 CMake 静态链进 `libentry.so`：

```bash
GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 CC=<ccwrap> \
  go build -buildmode=c-archive -o libxray.a .
```

代价是产物体积大（约 99 MB），换来没有 SONAME 问题。

---

## 6. 依赖补丁 1：xray-core 的 tun

**原因** 如第 1 节所述，openharmony 下 `GOOS == "linux"`，于是 `proxy/tun/tun_linux.go`
会被编进来，而它依赖 `netlink`——OpenHarmony 上没有可用路径。同时我们要走
「App 把 VpnExtensionAbility 拿到的 tun fd 直接交给内核」这条路。

**改法**（两个文件）

1. 新增 `proxy/tun/tun_openharmony.go`，`//go:build openharmony`，基于 fd 的 tun 实现（仿 `tun_android.go`）。
2. 收窄 Linux 分支的构建标签：

```
- //go:build linux && !android
+ //go:build linux && !android && !openharmony
```

---

## 7. 依赖补丁 2：gVisor 的 isSocketFD

**现象** VPN 建起来了，但内核起不动：

```
startVpnTun code=1 lastErr=unix.Fstat(35,...) failed: permission denied
```

**原因** gVisor 的 fdbased endpoint 用 `fstat` 判断 fd 是不是 socket，失败就当致命错误。
OpenHarmony 对 VpnExtensionAbility 创建的 tun fd 拒绝 `fstat`（EACCES），
但 `read`/`write` 是放行的。

**改法** `gvisor/pkg/tcpip/link/fdbased/endpoint.go` 的 `isSocketFD`：fstat 失败不再抛错，
按「非 socket」处理，从而走 `readv()` 分发——这本来就是 tun 设备该走的路径。

```go
if err := unix.Fstat(fd, &stat); err != nil {
	return false, nil
}
```

> 设备日志里还能翻到打补丁之前那条 `code=1`，正好是这条补丁属于「承重」而非装饰的证据。

---

## 8. 必须匿名导入 distro/all

不导入的话协议注册和 JSON loader 都不在，`StartInstance` 起不来：

```go
_ "github.com/xtls/xray-core/main/distro/all"
```

另外 `core.StartInstance` 内部已经调过 `instance.Start()`，不要再手动调一次。

---

## 9. 运行期问题（编译期看不出来）

### 9.1 VPN 路由回环

App 自己的出站流量又被打回 tun，形成死循环。光靠 `protectProcessNet()` 不够，
还要在 `VpnConfig` 里把本应用排除掉：

```ts
blockedApplications: ['com.xii.v2rayh']   // MyVpnExtAbility.ets
```

### 9.2 日志文件拉不下来

Go 创建的文件权限是 0600，`hdc` 读不到。改成先在 ArkTS 侧预创建日志文件（0660），
Go 只负责往里写。位置：

```
/data/app/el2/100/base/com.xii.v2rayh/haps/entry/files/{vpn.log,xray_error.log}
```

顺带一提：hilog 缓冲区转得很快，调内核问题基本只能靠落盘日志。

---

## 10. CI 踩的坑

### 10.1 OpenHarmony SDK 包的内部结构

`ohos-sdk-windows_linux-public.tar.gz` 有 **2.5 GB**，但它只是个容器，里面是按组件分的 zip：

```
linux/
linux/ets-linux-x64-6.1.0.31-Release.zip
linux/native-linux-x64-6.1.0.31-Release.zip   <-- 只要这个
```

所以 CI 里用 `tar --wildcards 'linux/native-*.zip'` 只抽 native，体积和时间都省掉绝大部分。

### 10.2 换行符

仓库 vendored 了 xray-core / gvisor 的 Go 源码，Windows 检出会把 LF 换成 CRLF。
加 `.gitattributes`（`* text=auto eol=lf` + 二进制白名单）钉住。

### 10.3 `.gitignore` 把目录一起吞了

`/native/tools/ccwrap`（本意是忽略编译出来的可执行文件）会**同时**匹配同名目录
`native/tools/ccwrap/`，结果 `ccwrap.go` 压根没进仓库；而且脚本原本把产物写到
`tools/ccwrap`，正好跟目录撞名。改成产物落到 `native/tools/bin/`。

### 10.4 gh 不认 ALL_PROXY

`gh` 走 Go 的 HTTP 栈，这里只认 `HTTPS_PROXY` / `HTTP_PROXY`：

```powershell
$env:HTTPS_PROXY="socks5://127.0.0.1:10808"
$env:HTTP_PROXY=$env:HTTPS_PROXY
```

### 10.5 上游版本号有两套体系

GitHub release tag 是 `v26.3.27`，Go module 版本是 `v1.260327.0`。
自动检查更新必须比 **module 版本**（问 `proxy.golang.org/<mod>/@latest`），
比 release tag 会永远判定「有新版本」。设备日志里内核自报 `Xray 26.3.27` 正好印证了这一点。

---

## 11. 在托管 runner 上编 HAP（已解决）

目标很明确：让 GitHub Actions 直接产出可安装的 HAP，做成 ClashBox 那种 release。

**结论：已解决。** 早期试的是公开 OpenHarmony SDK + 手工 hvigor，卡在 SDK 许可协议；
现在改用华为 **Command Line Tools（CLT for Linux）**：它内嵌 HarmonyOS SDK，
`devecocli`（npm `@deveco/deveco-cli`）官方支持 Linux，只要把
`DEVECO_CLI_CLT_PATH` 指向解压后的 `command-line-tools` 即可。CLT 只需一次性
放进 tag 为 `clt` 的 release（或配置 `CLT_ARCHIVE_URL`），之后
`.github/workflows/build-hap.yml` 会全自动构建未签名 HAP 并发 release。
详见 README 的 CI 一节。

下面是早期 OpenHarmony SDK 路线的记录（历史，供参考）：

可行性判断：HarmonyOS 工程要鸿蒙 SDK，而它只随 DevEco Studio 分发，华为没有放到任何公开镜像
（`repo.huaweicloud.com` 上只有 OpenHarmony SDK，和一个 13 KB 的 `ndk-1.0.tar.gz` 空壳）。
所以只能绕到 OpenHarmony SDK。逐一验证：

**能通的**

| 事项 | 结果 |
| --- | --- |
| `@ohos/hvigor` / `@ohos/hvigor-ohos-plugin` | `repo.harmonyos.com/npm` 公开可拉，版本与本地一致（6.26.8） |
| OH SDK 组件 | 2.5 GB 的容器里是分组件 zip：`ets` / `js` / `native` / `previewer` / `toolchains`，`apiVersion` 都是 23 |
| VPN 能力 | `ets/api/@ohos.net.vpnExtension.d.ts` **存在** —— 之前最担心的点不成立 |
| `hvigorfile.ts` 解析 | 必须把 hvigor 装进**工程目录**（node 从该文件往上找 `node_modules`），装到别处会 `Cannot find module '@ohos/hvigor-ohos-plugin'` |

**踩到的坑（都不显然）**

1. `For the OpenHarmony project, Please configure compileSdkVersion in the product`
   —— `runtimeOS: "OpenHarmony"` 时 product 里必须有 `compileSdkVersion`，HarmonyOS 模式没这个字段。
2. `00308018 The SDK management mode has changed`（报错信息极其误导）
   —— 真因在 `@ohos/sdkmanager-common` 的 `getLocation()`：

   ```js
   if (isValidApiVersion(component.getFullApiVersion()))
       return path.resolve(sdkRoot, `${fullApiVersion}`, componentPath);  // 带 apiVersion 这一层
   return path.resolve(sdkRoot, componentPath);
   ```

   我们的组件都带 `apiVersion`，所以期望路径是 `openharmony/23/ets`，
   而组件被平铺在 `openharmony/ets` → 被判为"位置不对" → 报成 SDK 模式变了。
   顺带：`default/` 下还得有 `sdk-pkg.json`。另外**别用 symlink**（`path.resolve` 是词法比较）。
3. `The SDK license agreement is not accepted` —— **真正卡死的地方**。

**为什么卡死**

许可接受记录是 `<SDK根>/licenses/<licenseId>.sha256`，内容必须等于
**从华为许可服务实时下载的许可文本的 sha256**（见 `core/license/license-manager.js`）。
CI 里没有这份记录，而合成它等于复刻 hvigor 的 GRS 许可查询/下载流程。
本机也没有 `licenses/` 目录可拿（DevEco 自带的鸿蒙 SDK 不需要它）。

即便绕过许可，后面还有 API 23 vs 工程实际使用的 24/26 接口的差距要挨个降级 —— 所以这条路性价比很低。

**早期结论**：当时可行的是 self-hosted runner，或本机跑 `scripts/release.ps1`。
现在托管 Linux runner + CLT 已经能直接出包，本机脚本保留给一次性构建/调试用。

---

## 附：一键重编

```bash
# Linux / CI
OHOS_GO=/path/to/ohos-go OHOS_SDK=/path/to/ohos-sdk ./native/build_libxray.sh
```

```powershell
# Windows
.\native\build_libxray.ps1 -OHOS_GO C:\ohos-go `
  -OHOS_SDK "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony"
```
