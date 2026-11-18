#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    case "${1:-}" in
        0|remove|purge)
            systemctl stop openresty.service >/dev/null 2>&1 || true
            systemctl disable openresty.service >/dev/null 2>&1 || true
            ;;
    esac
fi

exit 0
