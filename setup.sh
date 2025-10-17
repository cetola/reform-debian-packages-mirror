#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

. ./common.sh

# Release    pattern     pinning   Example
# -------------------------------------------
# Codename   ?codename   n=        sid
# Label      n.a.        l=        Debian
# Suite      ?archive    a=        unstable
# Origin     ?origin     o=        Debian
#

if ! test -d "$REPREPRO_BASE_DIR"; then
	mkdir -p "$REPREPRO_BASE_DIR/conf"
	cat >"$REPREPRO_BASE_DIR/conf/distributions" <<EOF
Codename: $OURSUITE
Label: $OURLABEL
Suite: $OURSUITE
Origin: $OURORIGIN
Architectures: $HOST_ARCH $(test "$BUILD_ARCH" = "$HOST_ARCH" || echo "$BUILD_ARCH") source
Components: main
UDebComponents: main
Contents: .xz
Description: updated packages for mnt reform
EOF
	# if OURSUITE is backports, also add the base suite
	case $OURSUITE in
	*-backports)
		cat >>"$REPREPRO_BASE_DIR/conf/distributions" <<EOF

Codename: ${OURSUITE%-backports}
Label: $OURLABEL
Suite: ${OURSUITE%-backports}
Origin: $OURORIGIN
Architectures: $HOST_ARCH $(test "$BUILD_ARCH" = "$HOST_ARCH" || echo "$BUILD_ARCH") source
Components: main
UDebComponents: main
Contents: .xz
Description: updated packages for mnt reform
EOF
		;;
	esac
	cat >"$REPREPRO_BASE_DIR/conf/options" <<EOF
verbose
EOF
	reprepro export
fi

if [ ! -d "$chdistdata" ]; then
	chdist_base create
fi

components="main non-free-firmware"

{
	echo "deb-src $MIRROR $BASESUITE $components"
	case $BASESUITE in
	experimental | rc-buggy)
		echo "deb-src $MIRROR unstable $components"
		;;
	unstable | sid | testing) : ;;
	*-backports)
		echo "deb-src $MIRROR ${BASESUITE%-backports} $components"
		echo "deb-src $MIRROR ${BASESUITE%-backports}-updates $components"
		echo "deb-src http://security.debian.org/debian-security ${BASESUITE%-backports}-security $components"
		;;
	*)
		# assume this is a stable release
		echo "deb-src $MIRROR $BASESUITE-updates $components"
		echo "deb-src http://security.debian.org/debian-security $BASESUITE-security $components"
		;;
	esac
} >"$chdistdata/base/etc/apt/sources.list"
mkdir -p "$chdistdata/base/etc/apt/apt.conf.d"
echo 'Acquire::Check-Valid-Until "false";' >"$chdistdata/base/etc/apt/apt.conf.d/99mmdebstrap"

chdist_base apt-get update --error-on=any

mkdir -p changes buildlogs
