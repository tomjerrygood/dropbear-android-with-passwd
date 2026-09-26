#!/bin/bash
set -e
set -x
VERSION=2018.76

PREFIX=/tmp/dropbear-android
HOST=arm-linux-androideabi
export TOOLCHAIN="$TOOLCHAIN"
export PATH="$TOOLCHAIN/bin:$PATH"
EXTRA_CFLAGS=""
echo "=== Download dropbear source ==="
# Download the latest version of dropbear SSH
if [ ! -f ./dropbear-$VERSION.tar.bz2 ]; then
    wget -O ./dropbear-$VERSION.tar.bz2 https://matt.ucc.asn.au/dropbear/releases/dropbear-$VERSION.tar.bz2
fi
echo "=== Extract source ==="
tar -xjf dropbear-${VERSION}.tar.bz2
echo "=== Apply patch ==="
cd dropbear-${VERSION}
patch -p1 -N --no-backup < ../android-compat.patch


# 修改 default_options.h 中的 SFTPSERVER_PATH
sed -i 's|#define SFTPSERVER_PATH "/usr/libexec/sftp-server"|#define SFTPSERVER_PATH "/system/xbin/sftp-server"|' default_options.h

# 修改 debian/rules 中的 SFTPSERVER_PATH
sed -i 's|SFTPSERVER_PATH="\"/usr/lib/sftp-server\""|SFTPSERVER_PATH="\"/system/xbin/sftp-server\""|' debian/rules

# ==========新增这两行：直接修改sysoptions.h，开启sftp子系统并写死路径==========
sed -i 's/#define DROPBEAR_SFTPSERVER 0/#define DROPBEAR_SFTPSERVER 1/' sysoptions.h
sed -i 's|#define SFTPSERVER_PATH.*|#define SFTPSERVER_PATH "/system/xbin/sftp-server"|' sysoptions.h


cd -
echo "=== Run configure ==="
cd dropbear-${VERSION}
./configure \
  --host=${HOST} \
  --prefix=${PREFIX} \
  --disable-zlib \
  --disable-static \
  --disable-shadow \
  --disable-utmp \
  --disable-pty \
  --disable-syslog \
  --disable-lastlog \
  CFLAGS="${EXTRA_CFLAGS} -Os"
echo "=== Provide fake stderr for bionic ==="
cat > compat-stderr.c << 'EOF'
#include <stdio.h>
#include <string.h>

/* bionic internal FILE layout */
typedef struct __sFILE {
    unsigned char *_p;
    int _r;
    int _w;
    short _flags;
    short _file;
    struct __sFILEAUX *aux;
    unsigned char *_base;
    int _size;
    int _bfsize;
    int _off;
    void *lock;
} sFILE_t;

static char __buf_stderr[1];
static sFILE_t __stderr_buf = {
    .aux = 0,
    .base = __buf_stderr,
    .off = 0,
    .lock = 0,
    .flags = 0x0200,
    .bfsize = 0,
    .p = __buf_stderr,
    .r = 0,
    .w = 0,
    .size = 0,
    .file = 2
};

__attribute__((weak)) FILE *stderr = (FILE *)&__stderr_buf;
EOF

echo "=== make clean 清除旧编译产物，避免残留dbclient目标文件 ==="
make clean
echo "=== Build libtomcrypt first (serial to avoid race conditions) ==="
make libtomcrypt -j1
echo "=== Compile compat-stderr.o ==="
${HOST}-gcc -c compat-stderr.c -o compat-stderr.o
echo "=== Start make: 编译 dropbear dropbearkey scp (serial build) ==="
make -j1 PROGRAMS="dropbear dropbearkey scp" CFLAGS="${EXTRA_CFLAGS} -Os" LDFLAGS="compat-stderr.o"
make install PROGRAMS="dropbear dropbearkey scp"
echo "=== Copy binaries ==="
mkdir -p ../target/arm
cp ${PREFIX}/sbin/dropbear ../target/arm/
cp ${PREFIX}/bin/dropbearkey ../target/arm/
cp ${PREFIX}/bin/scp ../target/arm/
echo "=== Strip ==="
${HOST}-strip ../target/arm/dropbear
${HOST}-strip ../target/arm/dropbearkey
${HOST}-strip ../target/arm/scp
echo "Build done, binaries in target/arm/"
ls -lh ../target/arm/
