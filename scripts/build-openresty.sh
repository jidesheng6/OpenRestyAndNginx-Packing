#!/usr/bin/env bash
# Build OpenResty for Windows (MINGW64) from the official source tarball.
# Must be executed inside an MSYS2 MINGW64 shell.
set -euo pipefail

: "${OPENRESTY_VERSION:?OPENRESTY_VERSION is required}"

if [[ "${MSYSTEM:-}" != "MINGW64" ]]; then
  echo "error: run this script from the MSYS2 MINGW64 shell (MSYSTEM=$MSYSTEM)" >&2
  exit 1
fi

WORKSPACE="${WORKSPACE_DIR:-$PWD}"
BUILD_ROOT="$WORKSPACE/.build"
CACHE_DIR="$WORKSPACE/.cache"
SRC_DIR="$BUILD_ROOT/openresty-$OPENRESTY_VERSION"
STAGE_DIR="$BUILD_ROOT/stage/openresty"

PCRE_VER="${PCRE_VER:-pcre2-10.49}"
ZLIB_VER="${ZLIB_VER:-zlib-1.3.2}"
OPENSSL_VER="${OPENSSL_VER:-openssl-3.5.9}"
JOBS="${JOBS:-$(nproc)}"

fetch() {
  local url="$1" dest="$2"
  if [[ -s "$dest" ]]; then
    echo "cache hit: $dest"
    return 0
  fi
  echo "downloading: $url"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -o "$dest" "$url"
}

mkdir -p "$CACHE_DIR" "$BUILD_ROOT"
fetch "https://openresty.org/download/openresty-$OPENRESTY_VERSION.tar.gz" \
      "$CACHE_DIR/openresty-$OPENRESTY_VERSION.tar.gz"
fetch "https://github.com/openssl/openssl/releases/download/$OPENSSL_VER/$OPENSSL_VER.tar.gz" \
      "$CACHE_DIR/$OPENSSL_VER.tar.gz"
ZLIB_TAG="${ZLIB_VER#zlib-}"
fetch "https://github.com/madler/zlib/releases/download/v$ZLIB_TAG/$ZLIB_VER.tar.gz" \
      "$CACHE_DIR/$ZLIB_VER.tar.gz"
fetch "https://github.com/PCRE2Project/pcre2/releases/download/$PCRE_VER/$PCRE_VER.tar.gz" \
      "$CACHE_DIR/$PCRE_VER.tar.gz"

rm -rf "$SRC_DIR" "$STAGE_DIR"
mkdir -p "$SRC_DIR" "$STAGE_DIR"
tar -xzf "$CACHE_DIR/openresty-$OPENRESTY_VERSION.tar.gz" -C "$BUILD_ROOT"

mkdir -p "$SRC_DIR/objs/lib"
tar -xzf "$CACHE_DIR/$OPENSSL_VER.tar.gz" -C "$SRC_DIR/objs/lib"
tar -xzf "$CACHE_DIR/$ZLIB_VER.tar.gz" -C "$SRC_DIR/objs/lib"
tar -xzf "$CACHE_DIR/$PCRE_VER.tar.gz" -C "$SRC_DIR/objs/lib"

for p in "$SRC_DIR"/patches/openssl-*-sess_set_get_cb_yield.patch; do
  if [[ -f "$p" ]]; then
    echo "applying $(basename "$p")"
    (cd "$SRC_DIR/objs/lib/$OPENSSL_VER" && patch -p1 < "$p")
  fi
done

cd "$SRC_DIR"
./configure \
  --with-cc=gcc \
  --platform=msys \
  --prefix="$STAGE_DIR" \
  --with-cc-opt='-DFD_SETSIZE=1024' \
  --sbin-path=nginx.exe \
  --with-pcre-jit \
  --without-http_rds_json_module \
  --without-http_rds_csv_module \
  --without-lua_rds_parser \
  --with-ipv6 \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-http_v2_module \
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
  --with-http_gunzip_module \
  --with-select_module \
  --with-luajit-xcflags="-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT" \
  --with-pcre="objs/lib/$PCRE_VER" \
  --with-zlib="objs/lib/$ZLIB_VER" \
  --with-openssl="objs/lib/$OPENSSL_VER" \
  -j"$JOBS"

make -j"$JOBS"
make install

cd "$STAGE_DIR"

if [[ ! -f nginx.exe ]]; then
  echo "error: nginx.exe was not installed into $STAGE_DIR" >&2
  find . -maxdepth 3 -type f | head -n 80 >&2
  exit 1
fi

# Copy the MinGW runtime DLLs that nginx.exe actually links against, so the
# installer works on machines without an MSYS2 installation.
ldd nginx.exe | awk '/\/mingw64\/bin\// { print $3 }' | sort -u | while read -r dll; do
  if [[ -f "$dll" ]]; then
    echo "bundling runtime DLL: $(basename "$dll")"
    cp -f "$dll" .
  fi
done

echo "STAGE_DIR=$STAGE_DIR"
echo "$STAGE_DIR" > "$BUILD_ROOT/stage-path.txt"
