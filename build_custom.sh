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

if [ -z "$(reprepro listfilter reform "Package (== wayfire)")" ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		cd ../wayfire
		git clone --recursive https://github.com/WayfireWM/wayfire.git wayfire-src

		WFCOMMIT=$(git rev-parse --short HEAD)
    WFDATE=$(date +%Y-%m-%d)
    WFVERTAR="0.8~$WFDATE"
		WFVER="wayfire_$WFVERTAR-git$WFCOMMIT"

    mv wayfire-src "$WFVER"
		# because debian meson.pm disables https://mesonbuild.com/Wrap-dependency-system-manual.html
		cp -Rv wayfire-debian-wrap-workaround/* "$WFVER/subprojects/"
		tar cvfz "$WORKDIR/wayfire_$WFVERTAR.orig.tar.gz" "$WFVER"

		cd "$WORKDIR"
		cp -Rv ../wayfire/debian "$WFVER"
    cd "$WFVER"
    echo "wayfire ($WFVERTAR-git$WFCOMMIT) reform; urgency=medium" > debian/changelog
    cat debian/changelog.tail >> debian/changelog

		sbuild --arch-all --arch-any --chroot $BASESUITE-$BUILD_ARCH $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		dcmd mv -v ../wayfire_*_amd64.changes "$ROOTDIR/changes"
		cd ..
	)
	rm -Rf "$WORKDIR"
fi

if [ -z "$(reprepro listfilter reform "Package (== reform-tools)")" ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://source.mnt.re/reform/reform-tools.git
		cd reform-tools
		sbuild --arch-all --arch-any --chroot $BASESUITE-$BUILD_ARCH $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		dcmd mv -v ../reform-tools_*_amd64.changes "$ROOTDIR/changes"
		cd ..
	)
	rm -Rf "$WORKDIR"
fi

if [ -z "$(reprepro listfilter reform "\$Source (== reform-handbook)")" ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://source.mnt.re/reform/reform-handbook.git
		cd reform-handbook
		sbuild --arch-all --arch-any --chroot $BASESUITE-$BUILD_ARCH $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		dcmd mv -v ../reform-handbook_*_amd64.changes "$ROOTDIR/changes"
		cd ..
	)
	rm -Rf "$WORKDIR"
fi
