#!/bin/bash
set -e
set -x
VERSION=2018.76

PREFIX=/tmp/dropbear-android
HOST=arm-linux-androideabi
export TOOLCHAIN="$TOOLCHAIN"
export PATH="$TOOLCHAIN/bin:$PATH"
# Android bionic libc static stderr fix
EXTRA_CFLAGS="-Dstderr=__stderrp -Dstdout=__stdoutp -Dstdin=__stdinp"
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

# ==========新增这两行：直接修改sysoptions.h，开启sftp子系统并写死路径==========
sed -i 's/#define DROPBEAR_SFTPSERVER 0/#define DROPBEAR_SFTPSERVER 1/' sysoptions.h
sed -i 's|#define SFTPSERVER_PATH.*|#define SFTPSERVER_PATH "/system/xbin/sftp-server"|' sysoptions.h

# ==========Fix libtomcrypt: add stdio.h include before its own headers=======
# libtomcrypt C files use fprintf(stderr,...) but don't include stdio.h
# Prepend #include <stdio.h> to tomlcrypt.h so all libtomcrypt files get it
LTC_H=src/libtomcrypt/src/headers/tomcrypt.h
if [ -f "$LTC_H" ]; then
  sed -i '1s/^/#include <stdio.h>\n/' "$LTC_H"
  echo "Patched $LTC_H with #include <stdio.h>"
fi

# Also patch individual libtommath files that may reference stderr
for f in $(find src/libtommath -name "*.c" 2>/dev/null); do
  if grep -q "fprintf.*stderr" "$f" && ! grep -q "#include <stdio.h>" "$f"; then
    sed -i '1s/^/#include <stdio.h>\n/' "$f"
  fi
done

cd -
echo "=== Run configure ==="
cd dropbear-${VERSION}
./configure \
  --host=${HOST} \
  --prefix=${PREFIX} \
  --disable-zlib \
  --enable-static \
  --disable-shadow \
  --disable-utmp \
  --disable-pty \
  --disable-syslog \
  --disable-lastlog \
  # 删掉 --enable-sftp-server ！！老版本不需要，上面sed已经开启宏
  CFLAGS="${EXTRA_CFLAGS} -Os"
echo "=== make clean 清除旧编译产物，避免残留dbclient目标文件 ==="
make clean
echo "=== Start make: 仅编译 dropbear dropbearkey ==="
make -j$(nproc) PROGRAMS="dropbear dropbearkey" CFLAGS="${EXTRA_CFLAGS} -Os"
make install PROGRAMS="dropbear dropbearkey" CFLAGS="${EXTRA_CFLAGS} -Os"
echo "=== Copy binaries ==="
mkdir -p ../target/arm
cp ${PREFIX}/sbin/dropbear ../target/arm/
cp ${PREFIX}/bin/dropbearkey ../target/arm/
echo "=== Strip ==="
${HOST}-strip ../target/arm/dropbear
${HOST}-strip ../target/arm/dropbearkey
echo "Build done, binaries in target/arm/"
ls -lh ../target/arm/
