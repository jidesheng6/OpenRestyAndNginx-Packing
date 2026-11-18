OpenResty @VERSION@ Linux 安装包
=================================

安装：
  RPM：sudo dnf install ./openresty-@VERSION@-1.@RPM_ARCH@.rpm
  DEB：sudo apt install ./openresty_@VERSION@-1_@DEB_ARCH@.deb

服务：
  sudo systemctl enable --now openresty
  sudo systemctl status openresty
  sudo systemctl restart openresty

配置：
  /usr/local/openresty/nginx/conf/nginx.conf

日志：
  /usr/local/openresty/nginx/logs/

健康检查：
  http://127.0.0.1/healthz

依赖：
  - glibc 2.28 或更高版本
  - resty 需要 perl；opm 还需要 curl、tar、gzip
  - OpenSSL、PCRE2、zlib 已静态内置，不需要额外安装

更多说明：
  https://github.com/jidesheng6/openresty-packaging
