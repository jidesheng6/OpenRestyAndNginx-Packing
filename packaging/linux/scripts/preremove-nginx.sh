#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    case "${1:-}" in
        0|remove|purge|upgrade)
            systemctl stop nginx.service >/dev/null 2>&1 || true
            systemctl disable nginx.service >/dev/null 2>&1 || true
            ;;
    esac
fi

exit 0
