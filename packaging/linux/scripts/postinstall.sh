#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable openresty.service >/dev/null 2>&1 || true
    systemctl restart openresty.service >/dev/null 2>&1 || true
fi

exit 0
