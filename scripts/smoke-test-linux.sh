#!/usr/bin/env bash
# Smoke-test the Linux RPM, DEB and portable tarball inside clean containers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
ARCH="${ARCH:?ARCH is required}"
OPENRESTY_VERSION="${OPENRESTY_VERSION:?OPENRESTY_VERSION is required}"
PLATFORM="${PLATFORM:-}"

case "$ARCH" in
  x86_64)
    PLATFORM="${PLATFORM:-linux/amd64}"
    DEB_ARCH=amd64
    ;;
  aarch64)
    PLATFORM="${PLATFORM:-linux/arm64}"
    DEB_ARCH=arm64
    ;;
  *)
    echo "error: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

RPM_FILE="$DIST_DIR/openresty-$OPENRESTY_VERSION-1.$ARCH.rpm"
DEB_FILE="$DIST_DIR/openresty_$OPENRESTY_VERSION-1_$DEB_ARCH.deb"
TAR_FILE="$DIST_DIR/openresty-$OPENRESTY_VERSION-linux-$ARCH.tar.gz"

for file in "$RPM_FILE" "$DEB_FILE" "$TAR_FILE"; do
  if [ ! -f "$file" ]; then
    echo "error: missing artifact: $file" >&2
    exit 1
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is required for smoke tests" >&2
  exit 1
fi

echo "==> RPM smoke test on AlmaLinux 8"
docker run --rm -i --platform "$PLATFORM" \
  -v "$DIST_DIR:/dist:ro" \
  -e RPM_FILE="/dist/$(basename "$RPM_FILE")" \
  almalinux:8 bash -s <<'EOS'
set -euo pipefail
dnf install -y --nogpgcheck "$RPM_FILE"
/usr/local/openresty/bin/openresty -t
/usr/local/openresty/bin/openresty
sleep 1
curl -fsS http://127.0.0.1/healthz
/usr/local/openresty/bin/openresty -s quit
rpm -e openresty
EOS

echo "==> RPM smoke test on AlmaLinux 9"
docker run --rm -i --platform "$PLATFORM" \
  -v "$DIST_DIR:/dist:ro" \
  -e RPM_FILE="/dist/$(basename "$RPM_FILE")" \
  almalinux:9 bash -s <<'EOS'
set -euo pipefail
dnf install -y --nogpgcheck "$RPM_FILE"
/usr/local/openresty/bin/openresty -t
/usr/local/openresty/bin/openresty
sleep 1
curl -fsS http://127.0.0.1/healthz
/usr/local/openresty/bin/openresty -s quit
rpm -e openresty
EOS

echo "==> DEB smoke test on Debian 12"
docker run --rm -i --platform "$PLATFORM" \
  -v "$DIST_DIR:/dist:ro" \
  -e DEB_FILE="/dist/$(basename "$DEB_FILE")" \
  debian:12 bash -s <<'EOS'
set -euo pipefail
apt-get update -qq
apt-get install -y -qq perl curl >/dev/null
dpkg -i "$DEB_FILE"
/usr/local/openresty/bin/openresty -t
/usr/local/openresty/bin/openresty
sleep 1
curl -fsS http://127.0.0.1/healthz
/usr/local/openresty/bin/openresty -s quit
dpkg -r openresty
EOS

echo "==> Portable tarball smoke test on Debian 12"
docker run --rm -i --platform "$PLATFORM" \
  -v "$DIST_DIR:/dist:ro" \
  -e TAR_FILE="/dist/$(basename "$TAR_FILE")" \
  debian:12 bash -s <<'EOS'
set -euo pipefail
apt-get update -qq
apt-get install -y -qq perl curl >/dev/null
mkdir -p /opt/openresty-test
tar -xzf "$TAR_FILE" -C /opt/openresty-test
cd /opt/openresty-test/openresty
./start.sh
sleep 1
curl -fsS http://127.0.0.1:8080/healthz
./bin/resty -e 'print("resty-ok\n")'
./stop.sh
EOS

echo "Linux smoke tests passed for $ARCH."
