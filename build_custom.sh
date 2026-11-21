#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues
# Copyright 2026 MNT Research GmbH

set -e
set -u

. ./common.sh

PKGVER=$(date +%Y%m%d)-1
PKGNAME=firmware-mnt-reform-nonfree_${PKGVER}_all.deb

echo "Building: $PKGNAME"

if [ ! -e $PKGNAME ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	cp -R firmware-mnt-reform-nonfree/* "$WORKDIR/"
	mkdir "$WORKDIR/DEBIAN"
	cat <<END >"$WORKDIR/DEBIAN/control"
Package: firmware-mnt-reform-nonfree
Version: $PKGVER
Section: non-free-firmware/kernel
Priority: optional
Architecture: all
Multi-Arch: foreign
Maintainer: Lucie Hartmann <lucie@mntre.com>
Description: Firmware blobs for various open hardware computers
 by MNT Research, primarily for Qualcomm SoCs.
END
	dpkg-deb --root-owner-group --build "$WORKDIR" .
	rm -Rf "$WORKDIR"
fi
