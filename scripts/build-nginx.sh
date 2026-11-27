#!/usr/bin/env bash
# Build vanilla nginx for Linux inside an AlmaLinux 8 container.
#
# Every module that nginx ships and can be built without extra runtimes is
# enabled. OpenSSL, PCRE2 and zlib are linked statically so the RPM/DEB/tarball
# only need glibc 2.28+ (plus the optional dynamic modules' own system libs).
# Packaging metadata is generated with nFPM from the same staged tree.
set -euo pipefail

: "${NGINX_VERSION:?NGINX_VERSION is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="${WORKSPACE_DIR:-$REPO_ROOT}"
ARCH="${ARCH:-$(uname -m)}"
BUILD_ROOT="${BUILD_ROOT:-$WORKSPACE/.build/nginx-linux-$ARCH}"
CACHE_DIR="$WORKSPACE/.cache"
DIST_DIR="${DIST_DIR:-$WORKSPACE/dist}"

CC="${CC:-gcc}"

# nfpm is a host-side packaging tool: its binary must match the build machine,
# which for native runs equals the target arch. For cross builds it stays x86_64.
case "$ARCH" in
  x86_64)
    PKG_GOARCH="${PKG_GOARCH:-amd64}"
    NFPM_HOST_ARCH=x86_64
    ;;
  aarch64)
    PKG_GOARCH="${PKG_GOARCH:-arm64}"
    NFPM_HOST_ARCH=arm64
    ;;
  sw64|sw_64)
    ARCH=sw64
    PKG_GOARCH="${PKG_GOARCH:-sw64}"
    NFPM_HOST_ARCH=x86_64
    : "${CROSS_COMPILE:?CROSS_COMPILE is required for sw64, e.g. sw_64sw6b-sunway-linux-gnu-}"
    CC="${CROSS_COMPILE}gcc"
    ;;
  *)
    echo "error: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

PCRE2_VERSION="${PCRE2_VERSION:-10.49}"
ZLIB_VERSION="${ZLIB_VERSION:-1.3.2}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.9}"
XCRYPT_VERSION="${XCRYPT_VERSION:-4.5.2}"
NFPM_VERSION="${NFPM_VERSION:-2.49.0}"
JOBS="${JOBS:-$(nproc)}"
# Set to 0 to skip the optional modules that need extra system dev libraries.
EXTRA_MODULES="${EXTRA_MODULES:-1}"

SRC_DIR="$BUILD_ROOT/nginx-$NGINX_VERSION"
DEPS_DIR="$BUILD_ROOT/deps"
INSTALL_ROOT="$BUILD_ROOT/install"
PKG_ROOT="$BUILD_ROOT/pkgroot"
CONF_DIR="$BUILD_ROOT/conf"
PORTABLE_PARENT="$BUILD_ROOT/portable"
PORTABLE_ROOT="$PORTABLE_PARENT/nginx"

if ! command -v dnf >/dev/null 2>&1; then
  echo "error: this script must be run inside AlmaLinux 8 (dnf not found)" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ] && [ "$ARCH" != "sw64" ]; then
  echo "error: this script must run as root inside the build container" >&2
  exit 1
fi

echo "==> Installing build dependencies"
dnf install -y --setopt=install_weak_deps=False \
  ca-certificates \
  curl \
  diffutils \
  findutils \
  gcc \
  gcc-c++ \
  gzip \
  kernel-headers \
  make \
  patch \
  perl \
  perl-Data-Dumper \
  perl-IPC-Cmd \
  perl-Time-Piece \
  tar \
  xz \
  libxml2-devel \
  libxslt-devel \
  gd-devel

fetch() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    echo "cache hit: $dest"
    return 0
  fi
  echo "downloading: $url"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -o "$dest" "$url"
}

mkdir -p "$CACHE_DIR" "$BUILD_ROOT" "$DIST_DIR" "$DEPS_DIR"

fetch "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" \
      "$CACHE_DIR/nginx-$NGINX_VERSION.tar.gz"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
      "$CACHE_DIR/openssl-$OPENSSL_VERSION.tar.gz"
fetch "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz" \
      "$CACHE_DIR/zlib-$ZLIB_VERSION.tar.gz"
fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz" \
      "$CACHE_DIR/pcre2-$PCRE2_VERSION.tar.gz"
fetch "https://github.com/besser82/libxcrypt/releases/download/v$XCRYPT_VERSION/libxcrypt-$XCRYPT_VERSION.tar.xz" \
      "$CACHE_DIR/libxcrypt-$XCRYPT_VERSION.tar.xz"

rm -rf "$SRC_DIR" "$INSTALL_ROOT" "$PKG_ROOT" "$CONF_DIR" "$PORTABLE_PARENT"
mkdir -p "$SRC_DIR" "$INSTALL_ROOT" "$PKG_ROOT" "$CONF_DIR" "$PORTABLE_ROOT"

tar -xzf "$CACHE_DIR/nginx-$NGINX_VERSION.tar.gz" -C "$BUILD_ROOT"
tar -xzf "$CACHE_DIR/openssl-$OPENSSL_VERSION.tar.gz" -C "$DEPS_DIR"
tar -xzf "$CACHE_DIR/zlib-$ZLIB_VERSION.tar.gz" -C "$DEPS_DIR"
tar -xzf "$CACHE_DIR/pcre2-$PCRE2_VERSION.tar.gz" -C "$DEPS_DIR"
tar -xJf "$CACHE_DIR/libxcrypt-$XCRYPT_VERSION.tar.xz" -C "$DEPS_DIR"

echo "==> Building static libxcrypt"
(
  cd "$DEPS_DIR/libxcrypt-$XCRYPT_VERSION"
  ./configure --prefix="$DEPS_DIR/libxcrypt" --disable-shared --enable-static
  make -j"$JOBS"
  make install
)

OPENSSL_PATCH="$REPO_ROOT/patches/openssl-3.5.5-sess_set_get_cb_yield.patch"
if [ -f "$OPENSSL_PATCH" ]; then
  echo "==> Applying bundled OpenSSL patch"
  if ! (cd "$DEPS_DIR/openssl-$OPENSSL_VERSION" && patch -p1 --forward < "$OPENSSL_PATCH"); then
    echo "warning: OpenSSL patch did not apply cleanly (may already be applied)" >&2
  fi
else
  echo "warning: OpenSSL patch not found: $OPENSSL_PATCH" >&2
fi

EXTRA_CONF=()
if [ "$EXTRA_MODULES" = "1" ]; then
  # Need libxml2/libxslt/libgd dev packages; built as dynamic modules so the
  # main binary stays free of those runtime dependencies.
  EXTRA_CONF+=(
    --with-http_xslt_module=dynamic
    --with-http_image_filter_module=dynamic
  )
fi

echo "==> Configuring nginx $NGINX_VERSION for Linux $ARCH"
cd "$SRC_DIR"
./configure \
  --prefix=/usr/local/nginx \
  --sbin-path=/usr/local/nginx/sbin/nginx \
  --conf-path=/usr/local/nginx/conf/nginx.conf \
  --error-log-path=logs/error.log \
  --http-log-path=logs/access.log \
  --pid-path=logs/nginx.pid \
  --lock-path=logs/nginx.lock \
  --modules-path=/usr/local/nginx/modules \
  --user=root \
  --group=root \
  --with-cc="$CC" \
  --with-ld-opt="-L$DEPS_DIR/libxcrypt/lib" \
  --with-compat \
  --with-file-aio \
  --with-threads \
  --with-pcre-jit \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_realip_module \
  --with-http_addition_module \
  --with-http_sub_module \
  --with-http_dav_module \
  --with-http_flv_module \
  --with-http_mp4_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_auth_request_module \
  --with-http_random_index_module \
  --with-http_secure_link_module \
  --with-http_degradation_module \
  --with-http_slice_module \
  --with-http_stub_status_module \
  --with-mail \
  --with-mail_ssl_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-stream_realip_module \
  "${EXTRA_CONF[@]}" \
  --with-pcre="$DEPS_DIR/pcre2-$PCRE2_VERSION" \
  --with-zlib="$DEPS_DIR/zlib-$ZLIB_VERSION" \
  --with-openssl="$DEPS_DIR/openssl-$OPENSSL_VERSION" \
  --with-openssl-opt="no-tests no-docs"

echo "==> Building nginx"
make -j"$JOBS"

echo "==> Installing into staging root"
make install DESTDIR="$INSTALL_ROOT"

NGINX_INSTALL="$INSTALL_ROOT/usr/local/nginx"
if [ ! -x "$NGINX_INSTALL/sbin/nginx" ]; then
  echo "error: nginx binary not found under $NGINX_INSTALL" >&2
  find "$INSTALL_ROOT" -maxdepth 5 -type f | head -n 80 >&2
  exit 1
fi

echo "==> Verifying static runtime dependencies"
if [ "$ARCH" = "sw64" ]; then
  echo "cross build: skipping host ldd verification"
else
  ldd "$NGINX_INSTALL/sbin/nginx" | tee "$BUILD_ROOT/ldd.txt"
  if grep -Eq 'libssl|libcrypto|libpcre2|libz\.so|libcrypt' "$BUILD_ROOT/ldd.txt"; then
    echo "error: nginx still links a dynamic third-party library" >&2
    exit 1
  fi
  if grep -q 'not found' "$BUILD_ROOT/ldd.txt"; then
    echo "error: nginx has an unresolved dynamic dependency" >&2
    exit 1
  fi
fi
"$NGINX_INSTALL/sbin/nginx" -V > "$BUILD_ROOT/nginx-V.txt" 2>&1 || true
cat "$BUILD_ROOT/nginx-V.txt"

echo "==> Staging portable tarball"
cp -a "$NGINX_INSTALL/." "$PORTABLE_ROOT/"
install -m 0644 "$REPO_ROOT/packaging/linux/nginx-portable-nginx.conf" \
  "$PORTABLE_ROOT/conf/nginx.conf"
mkdir -p "$PORTABLE_ROOT/conf/vhost"
install -m 0644 "$REPO_ROOT/packaging/linux/conf.d/README" \
  "$PORTABLE_ROOT/conf/vhost/README" 2>/dev/null || true
install -m 0755 "$REPO_ROOT/packaging/linux/portable/start-nginx.sh" "$PORTABLE_ROOT/start.sh"
install -m 0755 "$REPO_ROOT/packaging/linux/portable/stop-nginx.sh" "$PORTABLE_ROOT/stop.sh"
install -m 0755 "$REPO_ROOT/packaging/linux/portable/reload-nginx.sh" "$PORTABLE_ROOT/reload.sh"

VERSION="$NGINX_VERSION" ARCH="$ARCH" perl -pe '
  s/\{\{VERSION\}\}/nginx $ENV{VERSION}/g;
  s/Windows x64（MinGW64）/Linux $ENV{ARCH}（绿色版）/g;
  s/通过开始菜单中的“重启 nginx”/执行 .\/reload.sh/g;
  s/安装已成功完成/解压已完成/g;
' "$REPO_ROOT/installer/html/index.html" > "$PORTABLE_ROOT/html/index.html"

tar -C "$PORTABLE_PARENT" -czf "$DIST_DIR/nginx-$NGINX_VERSION-linux-$ARCH.tar.gz" nginx

echo "==> Staging RPM/DEB package root"
mkdir -p "$PKG_ROOT/usr/local"
cp -a "$NGINX_INSTALL" "$PKG_ROOT/usr/local/nginx"
install -d "$PKG_ROOT/usr/local/nginx/logs" "$PKG_ROOT/usr/local/nginx/conf/vhost"

# Keep conf as a conffile tree so upgrades never overwrite user changes.
cp -a "$PKG_ROOT/usr/local/nginx/conf/." "$CONF_DIR/"
rm -rf "$PKG_ROOT/usr/local/nginx/conf"
install -m 0644 "$REPO_ROOT/packaging/linux/nginx-system-nginx.conf" "$CONF_DIR/nginx.conf"
install -m 0644 "$REPO_ROOT/packaging/linux/conf.d/README" "$CONF_DIR/vhost/README" 2>/dev/null || true

VERSION="$NGINX_VERSION" ARCH="$ARCH" perl -pe '
  s/\{\{VERSION\}\}/nginx $ENV{VERSION}/g;
  s/Windows x64（MinGW64）/Linux $ENV{ARCH}（系统包）/g;
  s/通过开始菜单中的“重启 nginx”/通过 systemctl reload nginx/g;
' "$REPO_ROOT/installer/html/index.html" > "$PKG_ROOT/usr/local/nginx/html/index.html"

install -d "$PKG_ROOT/usr/sbin"
ln -sfn /usr/local/nginx/sbin/nginx "$PKG_ROOT/usr/sbin/nginx"
install -Dm644 "$REPO_ROOT/packaging/linux/nginx-service-nginx.conf" \
  "$PKG_ROOT/usr/lib/systemd/system/nginx.service"
install -Dm644 "$REPO_ROOT/packaging/linux/nginx-logrotate-nginx.conf" \
  "$PKG_ROOT/etc/logrotate.d/nginx"
install -d "$PKG_ROOT/usr/share/doc/nginx"
sed -e "s/@VERSION@/$NGINX_VERSION/g" \
    -e "s/@ARCH@/$ARCH/g" \
    "$REPO_ROOT/packaging/linux/package-README-nginx.txt" > "$PKG_ROOT/usr/share/doc/nginx/README.txt"

echo "==> Installing nFPM $NFPM_VERSION"
NFPM_DIR="$BUILD_ROOT/nfpm"
mkdir -p "$NFPM_DIR"
if [ ! -x "$NFPM_DIR/nfpm" ]; then
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 \
    "https://github.com/goreleaser/nfpm/releases/download/v$NFPM_VERSION/nfpm_${NFPM_VERSION}_Linux_${NFPM_HOST_ARCH}.tar.gz" \
    | tar -xz -C "$NFPM_DIR" nfpm
  chmod +x "$NFPM_DIR/nfpm"
fi

echo "==> Building RPM and DEB"
export PKG_ROOT CONF_DIR VERSION="$NGINX_VERSION" PKG_GOARCH
RPM_FILE="$DIST_DIR/nginx-$NGINX_VERSION-1.$ARCH.rpm"
DEB_FILE="$DIST_DIR/nginx_$NGINX_VERSION-1_$PKG_GOARCH.deb"

(
  cd "$REPO_ROOT/packaging/linux"
  "$NFPM_DIR/nfpm" package --config nfpm-nginx.yaml --packager rpm --target "$RPM_FILE"
  "$NFPM_DIR/nfpm" package --config nfpm-nginx.yaml --packager deb --target "$DEB_FILE"
)

echo "==> Artifacts"
ls -lh "$RPM_FILE" "$DEB_FILE" "$DIST_DIR/nginx-$NGINX_VERSION-linux-$ARCH.tar.gz"
