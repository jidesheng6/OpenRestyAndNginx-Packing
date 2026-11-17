# OpenResty Windows Setup

为 Windows x64 提供 OpenResty 的安装包构建流水线：GitHub Actions 定期检查 OpenResty 新版本，使用 MSYS2 / MinGW64 从官方源码编译，Inno Setup 打包为 `OpenResty-Setup-<version>-win64.exe`，并自动创建带版本号的 GitHub Release。

> 官方 Windows 二进制长期滞后（截至 2026-11 仅 `1.27.1.2` 可下载），因此本项目不再依赖官方 win64 zip，而是直接编译最新源码。

## 功能

- 每日检查 `https://openresty.org/en/download.html` 的最新版本，发布新 Release
- 支持手动指定版本重建：Actions -> Build Windows Installer -> Run workflow -> 填入 `1.31.8.1`
- 安装器基于 Inno Setup，包含 MIT 许可协议页
- 使用 WinSW 注册 Windows 服务 `OpenResty`（自包含 x64 版本，不依赖 .NET Framework）
- 首次安装可配置 HTTP 端口（默认 80），并检测端口占用
- 可选加入系统 PATH，卸载时自动移除（已打开的终端需重开才能读取新的 PATH）
- 安装完成后自动启动服务并做健康检查，可在完成页打开测试页
- 升级只替换程序文件，保留 `conf/`、`html/`、`logs/`
- 卸载时停止并移除服务，询问是否保留配置与日志
- 检测 Perl：`resty` 工具需要 Perl，服务本身不需要
- 构建流程内自动执行安装、升级保留配置、卸载的烟测

## 仓库结构

- `.github/workflows/build-release.yml`：版本探测、编译、打包、烟测、发布
- `scripts/build-openresty.sh`：MSYS2 下的源码编译与运行库收集
- `scripts/stage-payload.ps1`：整理安装树、下载 WinSW、生成服务配置
- `scripts/smoke-test.ps1`：安装/升级/卸载自动化验证
- `installer/openresty.iss`：Inno Setup 脚本
- `installer/conf/nginx.conf`：默认配置模板（含 `/healthz`）
- `installer/html/index.html`：安装完成后的测试首页

## 本地构建

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
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DAppVersion=1.31.8.1" "installer\openresty.iss"
```

产物位于 `installer/Output/OpenResty-Setup-<version>-win64.exe`。

## 安装器参数

交互安装直接双击即可。静默安装示例：

```powershell
# 安装到默认目录，监听 8080，并启动服务
.\OpenResty-Setup-1.31.8.1-win64.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /PORT=8080

# 只安装不启动服务
.\OpenResty-Setup-1.31.8.1-win64.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOSTART=1

# 卸载并删除配置与日志
& "$env:ProgramFiles\OpenResty\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /KEEPCONF=0
```

参数说明：

- `/PORT=<port>`：仅首次安装生效，写入 `conf/nginx.conf`；升级时忽略，避免覆盖已有配置
- `/NOSTART=1`：安装后不启动服务
- `/KEEPCONF=0`：卸载时删除 `conf/`、`html/`、`logs/`；默认保留

## 常用路径与服务

- 安装目录：`C:\Program Files\OpenResty`
- 服务名：`OpenResty`（WinSW 管理，自动启动）
- 配置：`conf\nginx.conf`
- 日志：`logs\error.log`、`logs\access.log`
- 健康检查：`http://127.0.0.1:<port>/healthz`
- 开始菜单提供启动、停止、重载、打开测试页、卸载

```powershell
Get-Service OpenResty
Start-Service OpenResty
Stop-Service OpenResty
Restart-Service OpenResty
```

## 版本发布流程

1. 每天 02:00 UTC 自动运行，或手动触发
2. 解析下载页最新源码版本；若 `v<version>` Release 已存在则跳过
3. 在 `windows-latest` 上用 MSYS2 编译 OpenResty 及 OpenSSL / PCRE2 / zlib
4. 打包并执行烟测（安装 -> 健康检查 -> 升级保留配置 -> 卸载）
5. 创建 Release `v<version>`，上传安装包与 SHA256

## 限制与说明

- Windows 版 nginx 仅支持 `select` 事件模型，不适合高并发生产环境；主要用于本地开发与测试
- 安装包未做代码签名，SmartScreen 可能提示未知发布者
- `resty` 命令需要系统安装 Perl（如 [Strawberry Perl](https://strawberryperl.com/)）
- 不支持 32 位系统

## License

本项目使用 MIT 协议。OpenResty 本身由 OpenResty Inc. 以 BSD 协议发布。
