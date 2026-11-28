# OpenResty & nginx Packaging

为 **OpenResty** 和 **nginx（mainline + stable）** 三条产品线统一提供 Windows 与 Linux 安装包。GitHub Actions 每天检查各上游最新版本，任一产品线有新版本即全量构建，并把所有产物发布到同一个滚动 Release `latest`。

仓库地址：`https://github.com/jidesheng6/OpenRestyAndNginx-Packing`

## 交付产物

统一发布在 [`latest`](https://github.com/jidesheng6/OpenRestyAndNginx-Packing/releases/tag/latest) Release，文件名自带各自版本号：

| 产品线 | Windows x64 | Linux |
|---|---|---|
| OpenResty | `OpenResty-Setup-<ver>-win64.exe` | `openresty-<ver>-1.<arch>.rpm` / `openresty_<ver>-1_<debarch>.deb` / `openresty-<ver>-linux-<arch>.tar.gz` |
| nginx mainline | `nginx-Setup-<ver>-win64.exe` | `nginx-<ver>-1.<arch>.rpm` / `nginx_<ver>-1_<debarch>.deb` / `nginx-<ver>-linux-<arch>.tar.gz` |
| nginx stable | 同上（stable 版本号） | 同上（stable 版本号） |

- `<arch>` 为 `x86_64` / `aarch64`，`<debarch>` 为 `amd64` / `arm64`。
- 每个 Windows 安装包另有 `.sha256`；整个 Release 附 `SHA256SUMS`。
- 当前版本示例：OpenResty 1.31.9.1、nginx mainline 1.31.10、nginx stable 1.30.8。

## 核心特性

- **单一工作流** `.github/workflows/build-all.yml`：解析三条线版本 → 并行构建 → 统一发布。
- **滚动 Release**：tag 固定 `latest`，每次构建覆盖更新，产物文件名区分版本；手动可勾选 `force` 强制重建。
- **Windows 安装器**：简体中文 Inno Setup；服务由 WinSW 注册；支持自定义端口（`/PORT=`）、加入 PATH、桌面快捷方式、完成页自动打开测试页。
- **升级保留配置**：`conf/`（含 `conf/vhost/`）、`html/`、`logs/` 升级不覆盖；Windows 卸载时可选择保留。
- **默认 vhost 支持**：主配置通过 `include vhost/*.conf;` 加载自定义虚拟主机。
- **完整烟测**：构建后自动安装、启动、`/healthz` 检查、升级保留配置验证、卸载清理。

## Windows 与 Linux 构建方式差异

- **OpenResty**：官方 Windows 二进制长期滞后，故 Windows 与 Linux 均从官方源码编译（MSYS2/MinGW64 + AlmaLinux 8）。Linux 静态内置 OpenSSL、PCRE2、zlib、libxcrypt。
- **nginx**：官方 Windows zip 与源码版本同步发布，故 Windows 直接使用官方二进制打包；Linux 从源码编译，开启**全部内置模块**（HTTP/2、HTTP/3、stream、mail、ssl、realip 等），`xslt` / `image_filter` 以动态模块随包提供，OpenSSL/PCRE2/zlib 静态内置。

两条 Linux 产品线的包都采用“自包含”策略：在 AlmaLinux 8 容器构建，基线 glibc 2.28，覆盖 RHEL/AlmaLinux/Rocky 8/9/10、Debian 10+、Ubuntu 20.04+。由于第三方库静态内置，OpenSSL 等发布安全更新后需重新构建发版。

## 仓库结构

公共工作流：

- `.github/workflows/build-all.yml`：三产品线版本解析、Windows/Linux 构建、烟测、统一发布到 `latest`

OpenResty 专用：

- `scripts/build-openresty.sh`：MSYS2 下 Windows 源码编译
- `scripts/build-linux.sh`：AlmaLinux 8 下 Linux 源码编译与打包
- `scripts/smoke-test-linux.sh`：Linux 产物容器烟测
- `scripts/stage-payload.ps1` / `scripts/smoke-test.ps1`：Windows 载荷与安装烟测
- `installer/openresty.iss` / `installer/conf/nginx.conf` / `installer/html/index.html`：安装器与配置模板
- `packaging/linux/`：`nfpm.yaml`、`nginx.conf`、`nginx-portable.conf`、`openresty.service`、`openresty.logrotate`、`scripts/`、`portable/`

nginx 专用：

- `scripts/build-nginx.sh`：AlmaLinux 8 下源码编译（全模块、静态依赖），预留 `sw64` 交叉编译入口
- `scripts/stage-nginx-payload.ps1`：下载官方 nginx/Windows zip 并整理载荷
- `scripts/smoke-test-nginx.ps1` / `scripts/smoke-test-nginx-linux.sh`：Windows/Linux 烟测
- `installer/nginx.iss` / `installer/html/nginx-index.html`：nginx 安装器与测试页
- `packaging/linux/nfpm-nginx.yaml`、`nginx-system-nginx.conf`、`nginx-portable-nginx.conf`、`nginx-service-nginx.conf`、`nginx-logrotate-nginx.conf`、`package-README-nginx.txt`、`conf.d/`、`scripts/*-nginx.sh`、`portable/*-nginx.sh`

## 本地构建

### OpenResty Windows（MSYS2 + Inno Setup）

```powershell
# MSYS2 MINGW64 终端
pacman -S --needed base-devel mingw-w64-x86_64-toolchain perl make wget patch zip unzip
$env:OPENRESTY_VERSION = "1.31.9.1"
bash scripts/build-openresty.sh

# PowerShell
./scripts/stage-payload.ps1 -Version 1.31.9.1
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DAppVersion=1.31.9.1" "installer\openresty.iss"
```

### nginx Windows（官方 zip + Inno Setup）

```powershell
$env:NGINX_VERSION = "1.31.10"   # 或 stable 版本号
./scripts/stage-nginx-payload.ps1 -Version $env:NGINX_VERSION
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DAppVersion=$env:NGINX_VERSION" "installer\nginx.iss"
```

### Linux（Docker + AlmaLinux 8）

```bash
# OpenResty（x86_64；aarch64 改 ARCH=aarch64 PKG_GOARCH=arm64）
docker run --rm -v "$PWD:/work" -w /work \
  -e OPENRESTY_VERSION=1.31.9.1 -e ARCH=x86_64 -e PKG_GOARCH=amd64 -e DIST_DIR=/work/dist \
  almalinux:8 bash scripts/build-linux.sh
ARCH=x86_64 OPENRESTY_VERSION=1.31.9.1 bash scripts/smoke-test-linux.sh

# nginx（x86_64；aarch64 同理）
docker run --rm -v "$PWD:/work" -w /work \
  -e NGINX_VERSION=1.31.10 -e ARCH=x86_64 -e PKG_GOARCH=amd64 -e DIST_DIR=/work/dist \
  almalinux:8 bash scripts/build-nginx.sh
ARCH=x86_64 VERSION=1.31.10 bash scripts/smoke-test-nginx-linux.sh
```

产物位于 `dist/`。

## 安装与使用

RPM：

```bash
sudo dnf install ./openresty-1.31.9.1-1.x86_64.rpm   # 或 nginx-1.31.10-1.x86_64.rpm
sudo systemctl enable --now openresty                 # nginx 则为 nginx
curl http://127.0.0.1/healthz
```

DEB：

```bash
sudo apt install ./openresty_1.31.9.1-1_amd64.deb
sudo systemctl enable --now openresty
curl http://127.0.0.1/healthz
```

常用路径：

| | OpenResty | nginx |
|---|---|---|
| 安装目录 | `/usr/local/openresty` | `/usr/local/nginx` |
| 主配置 | `/usr/local/openresty/nginx/conf/nginx.conf` | `/usr/local/nginx/conf/nginx.conf` |
| vhost 目录 | `<prefix>/nginx/conf/vhost/` | `<prefix>/conf/vhost/` |
| systemd 服务 | `openresty.service` | `nginx.service` |
| 健康检查 | `http://127.0.0.1/healthz` | `http://127.0.0.1/healthz` |
| 绿色版默认端口 | 8080 | 8080 |

> 若机器已安装发行版官方同类包，建议先卸载，避免文件路径冲突。

## 版本发布流程

1. 每天 02:00 UTC 自动运行，或在 Actions 手动触发（可勾选 `force`）。
2. 同时解析 OpenResty、nginx mainline、nginx stable 三个最新版本。
3. 与 `latest` Release 现有产物比对；若已是最新则跳过，否则并行构建全部产品线。
4. Windows：OpenResty 源码编译、nginx 用官方 zip；Linux：AlmaLinux 8 源码编译，x86_64/aarch64 双架构。
5. 容器中执行安装、`nginx -t`、启动、`/healthz`、升级保留配置、卸载等烟测。
6. 汇总全部产物到 `latest`，生成 `SHA256SUMS` 与中文发布说明（含三条线版本号）。

## 限制与说明

- Windows 版 nginx 仅支持 `select`/`poll` 事件模型，官方定位为 beta，不适合高并发生产；主要用于本地开发测试。
- Windows 安装包与 Linux 包均未做代码签名，SmartScreen 可能提示。
- Windows 的 OpenResty `resty` 命令需要系统安装 Perl（如 Strawberry Perl）；nginx 包不需要。
- Linux 包为自包含构建，静态库安全更新需重新发版；不替代发行版官方仓库包。
- SW64（申威）已在 `build-nginx.sh` 预留交叉编译入口，但当前 CI 无 SW64 runner 与公开工具链，暂无产物。
- 不支持 32 位系统。

## License

本项目使用 MIT 协议。OpenResty 与 nginx 均由各自上游以 BSD 协议发布。
