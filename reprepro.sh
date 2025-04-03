#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2023-2025 Johannes Schauer Marin Rodrigues

set -eu

. ./common.sh

for c in changes-custom/*.changes; do
  echo "including $c..." >&2
  reprepro include "$OURSUITE" "$c"
done

for ARCH in arm64 armhf i386 amd64; do
	for c in "changes-$ARCH"/*.changes; do
		[ -e "$c" ] || continue
		echo "including $c..." >&2
		reprepro include "$OURSUITE" "$c"
	done
done

# include binary out-of-tree driver modules
for d in reform-qcacld2*.deb fonts-reform-iosevka-term_2.3.0-1_all.deb; do
	echo "including $d..." >&2
	reprepro includedeb "$OURSUITE" "$d"
done

for p in $(reprepro --list-format '${source}\n' -T deb list "$OURSUITE" | sed 's/^\([^ (]\+\).*/\1/' | sort -u); do
	# source packages built in build_custom.sh or linux/build.sh must not get
	# removed, even if there is no file in ./patches
	case $p in
		linux) continue;;
	esac

	if [ ! -e "patches/$p" ]; then
		echo "patches/$p doesn't exist -- removing from repo"
		reprepro removesrc "$OURSUITE" "$p"
		continue
	fi

	if [ ! -x "patches/$p" ]; then
		echo "patches/$p is not executable --removing from repo"
		reprepro removesrc "$OURSUITE" "$p"
		continue
	fi
done
