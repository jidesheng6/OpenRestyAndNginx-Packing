#!/bin/sh
set -e

# OpenResty 的默认工作用户/组是 nobody。极简系统镜像中不一定存在，
# 因此安装时按需创建，避免 nginx -t 报告 getgrnam("nobody") 失败。
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

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable openresty.service >/dev/null 2>&1 || true
    systemctl restart openresty.service >/dev/null 2>&1 || true
fi

exit 0
