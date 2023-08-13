#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

. ./common.sh

if ! test -d "$REPREPRO_BASE_DIR"; then
	mkdir -p "$REPREPRO_BASE_DIR/conf"
	cat > "$REPREPRO_BASE_DIR/conf/distributions" <<EOF
Codename: $OURSUITE
Label: $OURSUITE
Architectures: $HOST_ARCH $(test "$BUILD_ARCH" = "$HOST_ARCH" || echo "$BUILD_ARCH")
Components: main
UDebComponents: main
Description: updated packages for mnt reform
EOF
	cat > "$REPREPRO_BASE_DIR/conf/options" <<EOF
verbose
EOF
	reprepro export
fi

if [ ! -d "$chdistdata" ]; then
	chdist_base create
fi

cat << END > "$chdistdata/base/etc/apt/sources.list"
deb-src $MIRROR $BASESUITE main
deb-src $MIRROR experimental main
END
chdist_base apt-get update

mkdir -p changes
