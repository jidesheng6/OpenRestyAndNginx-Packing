#!/bin/sh
set -e

# 极简系统镜像中不一定存在 nobody 用户/组，安装时按需创建。
if command -v id >/dev/null 2>&1 && ! id nobody >/dev/null 2>&1; then
    if command -v adduser >/dev/null 2>&1; then
        adduser --system --group nobody --no-create-home --disabled-password --shell /usr/sbin/nologin || true
    elif command -v useradd >/dev/null 2>&1; then
        if command -v getent >/dev/null 2>&1 && ! getent group nobody >/dev/null 2>&1; then
            groupadd -r nobody || true
        fi
        useradd -r -g nobody -s /usr/sbin/nologin nobody || true
    fi
fi

if command -v getent >/dev/null 2>&1 && ! getent group nobody >/dev/null 2>&1; then
    if command -v addgroup >/dev/null 2>&1; then
        addgroup --system nobody || true
    elif command -v groupadd >/dev/null 2>&1; then
        groupadd -r nobody || true
    fi
fi

mkdir -p /usr/local/nginx/logs /usr/local/nginx/conf/vhost

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable nginx.service >/dev/null 2>&1 || true
    systemctl restart nginx.service >/dev/null 2>&1 || true
fi

exit 0
