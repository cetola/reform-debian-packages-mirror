#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

. ./common.sh

# starting with 2.80, blender requires OpenGL 3.2+, so 2.79b is the last one
# that works on reform with imx8mq
#
# currently, building blender fails to builds with:
#
#     In file included from /usr/include/openvdb/tools/LevelSetRebuild.h:11,
#                      from /usr/include/openvdb/tools/GridTransformer.h:16,
#                      from /usr/include/openvdb/tools/Clip.h:16,
#                      from /<<PKGBUILDDIR>>/intern/openvdb/intern/openvdb_dense_convert.h:34,
#                      from /<<PKGBUILDDIR>>/intern/openvdb/openvdb_capi.cc:27:
#     /usr/include/openvdb/tools/VolumeToMesh.h:21:10: fatal error: tbb/task_scheduler_init.h: No such file or directory
#        21 | #include <tbb/task_scheduler_init.h>
#           |          ^~~~~~~~~~~~~~~~~~~~~~~~~~~
#     compilation terminated.
#
# This is because tbb dropped the tbb/task_scheduler_init.h header. Fixing this
# has to happen in openvdb but the proper fix will be to add support for onetbb
# to openvdb because tbb developers changed the name to onetbb:
# https://github.com/oneapi-src/oneTBB
# Tracking bug in Debian:
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1011215
# OpenVDB bug:
# https://github.com/AcademySoftwareFoundation/openvdb/issues/1366
#if [ -z "$(reprepro listfilter reform "\$Source (== blender)")" ]; then
#	env --chdir=blender \
#		BUILD_ARCH="$BUILD_ARCH" HOST_ARCH="$HOST_ARCH" \
#		BASESUITE="$BASESUITE" OURSUITE="$OURSUITE" \
#		./build.sh
#fi

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
