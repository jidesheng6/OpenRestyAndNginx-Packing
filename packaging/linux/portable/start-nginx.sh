#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$BASE/sbin/nginx" -p "$BASE/" -c conf/nginx.conf "$@"
