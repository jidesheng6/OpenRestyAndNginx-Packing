nginx @VERSION@ Linux @ARCH@ 系统安装包
========================================

本包由源码编译，静态内置 OpenSSL、PCRE2、zlib，运行时仅依赖
glibc（及可选的 xslt/image_filter 动态模块所需的系统库）。

可执行文件：
  /usr/local/nginx/sbin/nginx
  /usr/sbin/nginx （软链接）

服务管理：
  sudo systemctl enable --now nginx
  sudo systemctl reload nginx
  sudo systemctl stop nginx

配置：
  /usr/local/nginx/conf/nginx.conf
  /usr/local/nginx/conf/vhost/    自定义虚拟主机（升级保留）

日志：
  /usr/local/nginx/logs/access.log
  /usr/local/nginx/logs/error.log

健康检查：
  http://127.0.0.1/healthz

说明：
  - 配置目录 conf/ 在升级时不会被覆盖（dpkg conffile / rpm config noreplace）。
  - 移除包（remove）时保留配置；purge / erase 时按包管理器规则处理。
  - 本包未做代码签名。
