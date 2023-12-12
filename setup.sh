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
Label: $OURLABEL
Suite: $OURSUITE
Architectures: $HOST_ARCH $(test "$BUILD_ARCH" = "$HOST_ARCH" || echo "$BUILD_ARCH")
Components: main
UDebComponents: main
Description: updated packages for mnt reform
EOF
	# if OURSUITE is backports, also add the base suite
	case $OURSUITE in
		*-backports)
			cat >> "$REPREPRO_BASE_DIR/conf/distributions" <<EOF

Codename: ${OURSUITE%-backports}
Label: $OURLABEL
Suite: ${OURSUITE%-backports}
Architectures: $HOST_ARCH $(test "$BUILD_ARCH" = "$HOST_ARCH" || echo "$BUILD_ARCH")
Components: main
UDebComponents: main
Description: updated packages for mnt reform
EOF
		;;
	esac
	cat > "$REPREPRO_BASE_DIR/conf/options" <<EOF
verbose
EOF
	reprepro export
fi

if [ ! -d "$chdistdata" ]; then
	chdist_base create
fi

{
echo "deb-src $MIRROR $BASESUITE main";
case $BASESUITE in
	experimental)
		echo "deb-src $MIRROR unstable main"
		;;
	unstable) : ;;
	*-backports)
		echo "deb-src $MIRROR ${BASESUITE%-backports} main"
		echo "deb-src $MIRROR ${BASESUITE%-backports}-updates main"
		echo "deb-src http://security.debian.org/debian-security ${BASESUITE%-backports}-security main"
		;;
	*)
		# assume this is a stable release
		echo "deb-src $MIRROR $BASESUITE-updates main"
		echo "deb-src http://security.debian.org/debian-security $BASESUITE-security main"
		;;
esac;
} > "$chdistdata/base/etc/apt/sources.list"

chdist_base apt-get update

mkdir -p changes buildlogs
