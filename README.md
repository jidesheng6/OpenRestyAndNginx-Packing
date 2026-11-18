# OpenResty Packaging

为 OpenResty 提供 Windows 与 Linux 的安装包构建流水线。GitHub Actions 定期检查 OpenResty 新版本，从官方源码编译，并创建或更新对应版本的 GitHub Release。

- Windows：`OpenResty-Setup-<version>-win64.exe`
- Linux RPM：`openresty-<version>-1.<arch>.rpm`
- Linux DEB：`openresty_<version>-1_<arch>.deb`
- Linux 绿色版：`openresty-<version>-linux-<arch>.tar.gz`

> 官方 Windows 二进制长期滞后，因此 Windows 版本直接编译最新源码。Linux 版本同样从源码构建，并静态内置 OpenSSL、PCRE2、zlib、libxcrypt，避免不同发行版之间的动态库依赖问题。

## 功能

- 每日检查 `https://openresty.org/en/download.html` 的最新版本，发布新 Release
- 支持手动指定版本重建：Actions -> 构建全平台安装包 -> Run workflow -> 填入 `1.31.8.1`
- 同一个 `v<version>` Release 同时包含 Windows 与 Linux 产物
- Windows 安装器为简体中文界面，使用 Inno Setup 制作；服务由 WinSW 注册和管理
- Linux 提供 RPM、DEB 与绿色版 tar.gz，支持 `x86_64` 和 `aarch64`
- Linux 包使用 systemd 服务 `openresty`，默认配置监听 80 端口并提供 `/healthz`
- Linux 绿色版默认监听 8080，普通用户解压即可启动
- 升级保留配置：RPM/DEB 的 `nginx/conf` 作为配置文件处理，Windows 升级保留 `conf/`、`html/`、`logs/`
- 构建流程内自动执行安装、启动、健康检查和卸载烟测

## Linux 依赖策略

Linux 包采用“自包含”策略：

- OpenSSL、PCRE2、zlib、libxcrypt 静态编入 nginx，运行时不依赖 `libssl`、`libpcre2`、`libz`、`libcrypt`
- 二进制在 AlmaLinux 8 容器中构建，基线为 glibc 2.28
- 可覆盖 RHEL / AlmaLinux / Rocky 8、9、10，Debian 10+，Ubuntu 20.04+
- RPM/DEB 只声明 `glibc` 和少量基础工具依赖；`resty` 额外需要 perl，`opm` 还需要 `curl`、`tar`、`gzip`
- 由于第三方库是静态内置的，OpenSSL 等组件发布安全更新后需要重新构建并发布新包

这也意味着 Linux 包不是“发行版原生打包”的替代品，而是优先保证跨发行版可运行、安装简单。后续如需完全跟随发行版安全更新，可以再增加原生动态依赖的包。

## 仓库结构

- `.github/workflows/build-release.yml`：版本探测、Windows/Linux 构建、烟测、统一发布
- `scripts/build-openresty.sh`：MSYS2 下的 Windows 源码编译与运行库收集
- `scripts/build-linux.sh`：AlmaLinux 8 下的 Linux 源码编译、安装树、RPM/DEB/绿色版生成
- `scripts/smoke-test-linux.sh`：在 AlmaLinux 8/9 与 Debian 12 容器中验证 Linux 产物
- `scripts/stage-payload.ps1`：Windows 安装树、WinSW 服务配置生成
- `scripts/smoke-test.ps1`：Windows 安装/升级/卸载自动化验证
- `scripts/generate-icons.ps1`：生成 Windows 图标资源
- `installer/openresty.iss`：Inno Setup 脚本
- `installer/conf/nginx.conf`：Windows 默认配置模板
- `installer/html/index.html`：安装完成后的测试首页
- `packaging/linux/nginx.conf`：Linux 系统包默认配置
- `packaging/linux/nginx-portable.conf`：Linux 绿色版默认配置
- `packaging/linux/nfpm.yaml`：RPM/DEB 打包配置
- `packaging/linux/openresty.service`：systemd 服务
- `packaging/linux/openresty.logrotate`：日志轮转配置
- `packaging/linux/scripts/`：RPM/DEB 安装与卸载脚本
- `packaging/linux/portable/`：绿色版启动、停止、重载脚本与说明

## Windows 本地构建

前置条件：

- Windows 10 1809+ / Windows 11 x64
- 管理员 PowerShell
- [MSYS2](https://www.msys2.org/)（MINGW64 工具链）
- [Inno Setup 6](https://jrsoftware.org/isinfo.php)

```powershell
# 在 “MSYS2 MINGW64” 终端中执行
pacman -S --needed base-devel mingw-w64-x86_64-toolchain perl make wget patch zip unzip
$env:OPENRESTY_VERSION = "1.31.8.1"
bash scripts/build-openresty.sh

# 回到 PowerShell
./scripts/stage-payload.ps1 -Version 1.31.8.1

# 仅在需要重新生成图标时执行
./scripts/generate-icons.ps1

& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DAppVersion=1.31.8.1" "installer\openresty.iss"
```

产物位于 `installer/Output/OpenResty-Setup-<version>-win64.exe`。

## Linux 本地构建

前置条件：Docker，能够拉取 `almalinux:8`、`almalinux:9`、`debian:12` 镜像。

x86_64：

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  -e OPENRESTY_VERSION=1.31.8.1 \
  -e ARCH=x86_64 \
  -e PKG_GOARCH=amd64 \
  -e DIST_DIR=/work/dist \
  almalinux:8 \
  bash scripts/build-linux.sh

ARCH=x86_64 OPENRESTY_VERSION=1.31.8.1 bash scripts/smoke-test-linux.sh
```

aarch64（在 arm64 主机上）：

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  -e OPENRESTY_VERSION=1.31.8.1 \
  -e ARCH=aarch64 \
  -e PKG_GOARCH=arm64 \
  -e DIST_DIR=/work/dist \
  almalinux:8 \
  bash scripts/build-linux.sh

ARCH=aarch64 OPENRESTY_VERSION=1.31.8.1 bash scripts/smoke-test-linux.sh
```

产物位于 `dist/`。

## Linux 安装

RPM：

```bash
sudo dnf install ./openresty-1.31.8.1-1.x86_64.rpm
sudo systemctl enable --now openresty
curl http://127.0.0.1/healthz
```

DEB：

```bash
sudo apt install ./openresty_1.31.8.1-1_amd64.deb
sudo systemctl enable --now openresty
curl http://127.0.0.1/healthz
```

ARM64 请使用对应的 `aarch64.rpm` 或 `arm64.deb`。

常用路径与服务：

- 安装目录：`/usr/local/openresty`
- 配置：`/usr/local/openresty/nginx/conf/nginx.conf`
- 日志：`/usr/local/openresty/nginx/logs/`
- 服务：`openresty.service`
- 健康检查：`http://127.0.0.1/healthz`
- 命令行：`/usr/local/openresty/bin/openresty`、`resty`、`opm`

> 包名为 `openresty`，安装路径与官方包一致。如果机器上已经安装官方 OpenResty，建议先卸载官方包，避免文件冲突。

## Linux 绿色版

```bash
tar -xzf openresty-1.31.8.1-linux-x86_64.tar.gz
cd openresty
./start.sh
curl http://127.0.0.1:8080/healthz
./stop.sh
```

绿色版默认监听 8080，普通用户即可运行；需要 80 端口时修改 `nginx/conf/nginx.conf` 并以 root 运行。`resty`、`opm` 需要系统安装 perl。

## 版本发布流程

1. 每天 02:00 UTC 自动运行，或手动触发
2. 解析下载页最新源码版本；若 `v<version>` Release 已存在则跳过（勾选“强制重建”可覆盖已有 Release 附件）
3. 并行构建：
   - Windows x64：MSYS2 / MinGW64 + Inno Setup
   - Linux x86_64：AlmaLinux 8 容器，使用原生 x86_64 runner
   - Linux aarch64：AlmaLinux 8 容器，使用原生 arm64 runner
4. 在容器中安装 RPM/DEB/绿色版，执行 `nginx -t`、启动、`/healthz` 检查和卸载
5. 汇总所有产物，生成 `SHA256SUMS`
6. 创建或更新 Release `v<version>`，标题为 `OpenResty <version> Windows / Linux 安装包`

## 限制与说明

- Windows 版 nginx 仅支持 `select` 事件模型，不适合高并发生产环境；主要用于本地开发与测试
- Windows 安装包与 Linux 包均未做代码签名
- Windows 的 `resty` 需要系统安装 Perl（如 [Strawberry Perl](https://strawberryperl.com/)）
- Linux 包为自包含构建，OpenSSL 等静态库的安全更新需要重新发版
- Linux 包不替代各发行版官方仓库中的 OpenResty；如需要严格的发行版依赖策略，应另行生成原生依赖包
- 不支持 32 位系统

## License

本项目使用 MIT 协议。OpenResty 本身由 OpenResty Inc. 以 BSD 协议发布。
