#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$BASE/bin/openresty" -p "$BASE/nginx/" -c conf/nginx.conf -s quit
