#!/usr/bin/env bash
# Build OpenResty for Linux inside an AlmaLinux 8 container.
#
# The resulting nginx binary links OpenSSL, PCRE2 and zlib statically so the
# RPM/DEB/tarball can run on any glibc 2.28+ distribution. Packaging metadata is
# generated with nFPM from the same staged tree.
set -euo pipefail

: "${OPENRESTY_VERSION:?OPENRESTY_VERSION is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="${WORKSPACE_DIR:-$REPO_ROOT}"
ARCH="${ARCH:-$(uname -m)}"
BUILD_ROOT="${BUILD_ROOT:-$WORKSPACE/.build/linux-$ARCH}"
CACHE_DIR="$WORKSPACE/.cache"
DIST_DIR="${DIST_DIR:-$WORKSPACE/dist}"

case "$ARCH" in
  x86_64)
    PKG_GOARCH="${PKG_GOARCH:-amd64}"
    NFPM_ARCH=x86_64
    ;;
  aarch64)
    PKG_GOARCH="${PKG_GOARCH:-arm64}"
    NFPM_ARCH=arm64
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

SRC_DIR="$BUILD_ROOT/openresty-$OPENRESTY_VERSION"
DEPS_DIR="$SRC_DIR/objs/lib"
INSTALL_ROOT="$BUILD_ROOT/install"
PKG_ROOT="$BUILD_ROOT/pkgroot"
CONF_DIR="$BUILD_ROOT/conf"
PORTABLE_PARENT="$BUILD_ROOT/portable"
PORTABLE_ROOT="$PORTABLE_PARENT/openresty"

if ! command -v dnf >/dev/null 2>&1; then
  echo "error: this script must be run inside AlmaLinux 8 (dnf not found)" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
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
  xz

fetch() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    echo "cache hit: $dest"
    return 0
  fi
  echo "downloading: $url"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -o "$dest" "$url"
}

mkdir -p "$CACHE_DIR" "$BUILD_ROOT" "$DIST_DIR"

fetch "https://openresty.org/download/openresty-$OPENRESTY_VERSION.tar.gz" \
      "$CACHE_DIR/openresty-$OPENRESTY_VERSION.tar.gz"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
      "$CACHE_DIR/openssl-$OPENSSL_VERSION.tar.gz"
fetch "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz" \
      "$CACHE_DIR/zlib-$ZLIB_VERSION.tar.gz"
fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz" \
      "$CACHE_DIR/pcre2-$PCRE2_VERSION.tar.gz"
fetch "https://github.com/besser82/libxcrypt/releases/download/v$XCRYPT_VERSION/libxcrypt-$XCRYPT_VERSION.tar.xz" \
      "$CACHE_DIR/libxcrypt-$XCRYPT_VERSION.tar.xz"

rm -rf "$SRC_DIR" "$INSTALL_ROOT" "$PKG_ROOT" "$CONF_DIR" "$PORTABLE_PARENT"
mkdir -p "$SRC_DIR" "$INSTALL_ROOT" "$DEPS_DIR" "$PKG_ROOT" "$CONF_DIR" "$PORTABLE_ROOT"

tar -xzf "$CACHE_DIR/openresty-$OPENRESTY_VERSION.tar.gz" -C "$BUILD_ROOT"
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
  (cd "$DEPS_DIR/openssl-$OPENSSL_VERSION" && patch -p1 < "$OPENSSL_PATCH")
else
  echo "warning: OpenSSL patch not found: $OPENSSL_PATCH" >&2
fi

echo "==> Configuring OpenResty $OPENRESTY_VERSION for Linux $ARCH"
cd "$SRC_DIR"
./configure \
  --prefix=/usr/local/openresty \
  --with-cc=gcc \
  --with-ld-opt="-L$DEPS_DIR/libxcrypt/lib" \
  --with-compat \
  --with-file-aio \
  --with-threads \
  --with-pcre-jit \
  --without-http_rds_json_module \
  --without-http_rds_csv_module \
  --without-lua_rds_parser \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-stream_realip_module \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --without-mail_pop3_module \
  --without-mail_imap_module \
  --without-mail_smtp_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_addition_module \
  --with-http_auth_request_module \
  --with-http_secure_link_module \
  --with-http_random_index_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  --with-http_dav_module \
  --with-http_flv_module \
  --with-http_mp4_module \
  --with-http_slice_module \
  --with-http_gunzip_module \
  --with-luajit-xcflags="-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT" \
  --with-pcre="$DEPS_DIR/pcre2-$PCRE2_VERSION" \
  --with-zlib="$DEPS_DIR/zlib-$ZLIB_VERSION" \
  --with-openssl="$DEPS_DIR/openssl-$OPENSSL_VERSION" \
  --with-openssl-opt="no-tests no-docs" \
  -j"$JOBS"

echo "==> Building OpenResty"
make -j"$JOBS"

# Nginx's link line prefers libluajit-5.1.so over the .a archive. Relink
# against the static archive so the portable tarball does not depend on an
# absolute /usr/local/openresty/luajit/lib rpath.
echo "==> Relinking nginx against static LuaJIT"
LUAJIT_BUILD_LIB="$SRC_DIR/build/luajit-root/usr/local/openresty/luajit/lib"
if [ ! -f "$LUAJIT_BUILD_LIB/libluajit-5.1.a" ]; then
  echo "error: LuaJIT static archive not found under $LUAJIT_BUILD_LIB" >&2
  exit 1
fi
rm -f "$LUAJIT_BUILD_LIB"/libluajit-5.1.so*
(
  cd "$SRC_DIR/build/nginx-1.31.8"
  rm -f objs/nginx
  make -j"$JOBS"
)

echo "==> Installing into staging root"
make install DESTDIR="$INSTALL_ROOT"

OPENRESTY_INSTALL="$INSTALL_ROOT/usr/local/openresty"
if [ ! -x "$OPENRESTY_INSTALL/nginx/sbin/nginx" ]; then
  echo "error: nginx binary not found under $OPENRESTY_INSTALL" >&2
  find "$INSTALL_ROOT" -maxdepth 5 -type f | head -n 80 >&2
  exit 1
fi

mkdir -p "$OPENRESTY_INSTALL/bin"
if [ ! -e "$OPENRESTY_INSTALL/bin/openresty" ]; then
  ln -sfn ../nginx/sbin/nginx "$OPENRESTY_INSTALL/bin/openresty"
fi

echo "==> Verifying static runtime dependencies"
ldd "$OPENRESTY_INSTALL/nginx/sbin/nginx" | tee "$BUILD_ROOT/ldd.txt"
if grep -Eq 'libssl|libcrypto|libpcre2|libz\.so|libluajit|libcrypt' "$BUILD_ROOT/ldd.txt"; then
  echo "error: nginx still links a dynamic third-party library" >&2
  exit 1
fi
if grep -q 'not found' "$BUILD_ROOT/ldd.txt"; then
  echo "error: nginx has an unresolved dynamic dependency" >&2
  exit 1
fi
"$OPENRESTY_INSTALL/nginx/sbin/nginx" -V > "$BUILD_ROOT/nginx-V.txt" 2>&1 || true

echo "==> Staging portable tarball"
cp -a "$OPENRESTY_INSTALL/." "$PORTABLE_ROOT/"
install -m 0644 "$REPO_ROOT/packaging/linux/nginx-portable.conf" \
  "$PORTABLE_ROOT/nginx/conf/nginx.conf"
install -m 0755 "$REPO_ROOT/packaging/linux/portable/start.sh" "$PORTABLE_ROOT/start.sh"
install -m 0755 "$REPO_ROOT/packaging/linux/portable/stop.sh" "$PORTABLE_ROOT/stop.sh"
install -m 0755 "$REPO_ROOT/packaging/linux/portable/reload.sh" "$PORTABLE_ROOT/reload.sh"
sed -e "s/@VERSION@/$OPENRESTY_VERSION/g" -e "s/@ARCH@/$ARCH/g" \
  "$REPO_ROOT/packaging/linux/portable/README.txt" > "$PORTABLE_ROOT/README.txt"

VERSION="$OPENRESTY_VERSION" ARCH="$ARCH" perl -pe '
  s/\{\{VERSION\}\}/OpenResty $ENV{VERSION}/g;
  s/Windows x64（MinGW64）/Linux $ENV{ARCH}（绿色版）/g;
  s/通过开始菜单中的“重启 OpenResty”/执行 .\/stop.sh 后重新执行 .\/start.sh/g;
  s/安装已成功完成/解压已完成/g;
' "$REPO_ROOT/installer/html/index.html" > "$PORTABLE_ROOT/nginx/html/index.html"

tar -C "$PORTABLE_PARENT" -czf "$DIST_DIR/openresty-$OPENRESTY_VERSION-linux-$ARCH.tar.gz" openresty

echo "==> Staging RPM/DEB package root"
mkdir -p "$PKG_ROOT/usr/local"
cp -a "$OPENRESTY_INSTALL" "$PKG_ROOT/usr/local/openresty"
install -d "$PKG_ROOT/usr/local/openresty/nginx/logs"

# Keep nginx/conf as a conffile tree so upgrades never overwrite user changes.
cp -a "$PKG_ROOT/usr/local/openresty/nginx/conf/." "$CONF_DIR/"
rm -rf "$PKG_ROOT/usr/local/openresty/nginx/conf"
install -m 0644 "$REPO_ROOT/packaging/linux/nginx.conf" "$CONF_DIR/nginx.conf"

VERSION="$OPENRESTY_VERSION" ARCH="$ARCH" perl -pe '
  s/\{\{VERSION\}\}/OpenResty $ENV{VERSION}/g;
  s/Windows x64（MinGW64）/Linux $ENV{ARCH}（系统包）/g;
  s/通过开始菜单中的“重启 OpenResty”/通过 systemctl restart openresty/g;
' "$REPO_ROOT/installer/html/index.html" > "$PKG_ROOT/usr/local/openresty/nginx/html/index.html"

install -d "$PKG_ROOT/usr/bin"
ln -sfn /usr/local/openresty/bin/openresty "$PKG_ROOT/usr/bin/openresty"
ln -sfn /usr/local/openresty/bin/resty "$PKG_ROOT/usr/bin/resty"
ln -sfn /usr/local/openresty/bin/opm "$PKG_ROOT/usr/bin/opm"
if [ -x "$PKG_ROOT/usr/local/openresty/luajit/bin/luajit" ]; then
  ln -sfn /usr/local/openresty/luajit/bin/luajit "$PKG_ROOT/usr/bin/luajit"
fi

install -Dm644 "$REPO_ROOT/packaging/linux/openresty.service" \
  "$PKG_ROOT/usr/lib/systemd/system/openresty.service"
install -Dm644 "$REPO_ROOT/packaging/linux/openresty.logrotate" \
  "$PKG_ROOT/etc/logrotate.d/openresty"
install -d "$PKG_ROOT/usr/share/doc/openresty"
sed -e "s/@VERSION@/$OPENRESTY_VERSION/g" \
    -e "s/@RPM_ARCH@/$ARCH/g" \
    -e "s/@DEB_ARCH@/$PKG_GOARCH/g" \
    "$REPO_ROOT/packaging/linux/package-README.txt" > "$PKG_ROOT/usr/share/doc/openresty/README.txt"

echo "==> Installing nFPM $NFPM_VERSION"
NFPM_DIR="$BUILD_ROOT/nfpm"
mkdir -p "$NFPM_DIR"
if [ ! -x "$NFPM_DIR/nfpm" ]; then
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 \
    "https://github.com/goreleaser/nfpm/releases/download/v$NFPM_VERSION/nfpm_${NFPM_VERSION}_Linux_${NFPM_ARCH}.tar.gz" \
    | tar -xz -C "$NFPM_DIR" nfpm
  chmod +x "$NFPM_DIR/nfpm"
fi

echo "==> Building RPM and DEB"
export PKG_ROOT CONF_DIR VERSION="$OPENRESTY_VERSION" PKG_GOARCH
RPM_FILE="$DIST_DIR/openresty-$OPENRESTY_VERSION-1.$ARCH.rpm"
DEB_FILE="$DIST_DIR/openresty_$OPENRESTY_VERSION-1_$PKG_GOARCH.deb"

(
  cd "$REPO_ROOT/packaging/linux"
  "$NFPM_DIR/nfpm" package --config nfpm.yaml --packager rpm --target "$RPM_FILE"
  "$NFPM_DIR/nfpm" package --config nfpm.yaml --packager deb --target "$DEB_FILE"
)

echo "==> Artifacts"
ls -lh "$RPM_FILE" "$DEB_FILE" "$DIST_DIR/openresty-$OPENRESTY_VERSION-linux-$ARCH.tar.gz"
