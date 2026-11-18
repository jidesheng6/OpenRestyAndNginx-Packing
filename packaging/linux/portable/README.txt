OpenResty @VERSION@ Linux @ARCH@ 绿色版
========================================

启动：
  ./start.sh

停止：
  ./stop.sh

重新加载配置：
  ./reload.sh

默认地址：
  http://127.0.0.1:8080/
  健康检查：http://127.0.0.1:8080/healthz

目录说明：
  nginx/conf/nginx.conf  默认配置
  nginx/html/            测试首页
  nginx/logs/            日志与 pid
  bin/resty              OpenResty 命令行工具
  bin/opm                OpenResty 包管理器

说明：
  - 默认监听 8080，普通用户即可启动；如需 80 端口，请修改
    nginx/conf/nginx.conf 后以 root 运行。
  - 本绿色版已静态内置 OpenSSL、PCRE2 和 zlib，运行时只需要
    glibc 2.28 或更高版本。
  - resty 和 opm 需要系统安装 perl。
  - 如果从其他目录启动，请使用 ./start.sh，不要直接运行
    bin/openresty，否则会使用编译时的默认前缀。
