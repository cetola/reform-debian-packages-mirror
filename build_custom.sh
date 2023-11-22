#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

. ./common.sh

# simplified version of $our_version from build_patched.sh because the binary
# version is always equal to the source version here
our_version=$(reprepro --list-format '${version}\n' -T deb listfilter "$OURSUITE" "\$Source (== reform-tools)" | uniq)
their_version=$(curl --silent https://source.mnt.re/reform/reform-tools/-/raw/main/debian/changelog | dpkg-parsechangelog --show-field Version --file -)
if [ -z "$our_version" ] || dpkg --compare-versions "$our_version" lt "$their_version"; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://source.mnt.re/reform/reform-tools.git
		cd reform-tools
		if [ -n "${REFORM_TOOLS_BRANCH:-}" ]; then
			git switch "$REFORM_TOOLS_BRANCH"
		fi
		sbuild -d "$OURSUITE" --arch-all --arch-any --chroot $BASESUITE-$BUILD_ARCH $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		dcmd mv -v ../reform-tools_*"_${BUILD_ARCH}.changes" "$ROOTDIR/changes"
		cd ..
	)
	rm -Rf "$WORKDIR"
fi

our_version=$(reprepro --list-format '${version}\n' -T deb listfilter "$OURSUITE" "\$Source (== reform-handbook)" | uniq)
their_version=$(curl --silent https://source.mnt.re/reform/reform-handbook/-/raw/master/debian/changelog | dpkg-parsechangelog --show-field Version --file -)
if [ -z "$our_version" ] || dpkg --compare-versions "$our_version" lt "$their_version"; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://source.mnt.re/reform/reform-handbook.git
		cd reform-handbook
		sbuild -d "$OURSUITE" --arch-all --arch-any --chroot $BASESUITE-$BUILD_ARCH $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		dcmd mv -v ../reform-handbook_*"_${BUILD_ARCH}.changes" "$ROOTDIR/changes"
		cd ..
	)
	rm -Rf "$WORKDIR"
fi
