#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

BASESUITE=unstable
OURSUITE=reform
WORKDIR=$(mktemp --directory --tmpdir="$(pwd)")
PATCHDIR=$(realpath patches)
REPREPRO_BASE_DIR=$(realpath repo)
HTTP_PORT=7251
: "${MIRROR:=http://deb.debian.org/debian}"
# If we are in a git repository and if SOURCE_DATE_EPOCH is not set or set but
# null, use the timestamp of the latest git commit. Otherwise, use the provided
# value (if not null) or default to the timestamp of now.
if [ -z ${SOURCE_DATE_EPOCH:+x} ] && git -C . rev-parse 2>/dev/null; then
	SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
else
	: "${SOURCE_DATE_EPOCH:=$(date +%s)}"
fi
export SOURCE_DATE_EPOCH
export REPREPRO_BASE_DIR
HTTPD_PID=

export DEBEMAIL='robot <reform@reform.repo>'

cleanup() {
	if test -n "$HTTPD_PID"; then
		kill "$HTTPD_PID" || :
	fi
	if test -d "$WORKDIR"; then
		rm -Rf "$WORKDIR"
	fi
}

trap cleanup EXIT

python3 -m http.server --bind 127.0.0.1 --directory "$REPREPRO_BASE_DIR" "$HTTP_PORT" &
HTTPD_PID=$!

SRC_LIST_PATCHED="deb [ trusted=yes ] http://127.0.0.1:$HTTP_PORT/ $OURSUITE main"

BUILD_ARCH=$(dpkg --print-architecture)
HOST_ARCH=arm64

# the remaining code assumes that the native arch is different from the host arch
[ "$BUILD_ARCH" != "$HOST_ARCH" ]

DEB_BUILD_PROFILES="nobiarch nocheck noudeb"
if [ "$BUILD_ARCH" != "$HOST_ARCH" ]; then
	# FIXME: the cross profile must not be set during native build
	DEB_BUILD_PROFILES="cross $DEB_BUILD_PROFILES"
fi
export DEB_BUILD_PROFILES
export DEB_BUILD_OPTIONS="noautodbgsym nocheck noudeb"

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
ignore wrongdistribution
EOF
	reprepro export
fi

chdistdata=$(pwd)/chdist
chdist_base() {
	local cmd
	cmd=$1
	shift
	chdist "--data-dir=$chdistdata" "$cmd" base "$@"
}

if [ ! -d "$chdistdata" ]; then
	chdist_base create
fi

cat << END > "$chdistdata/base/etc/apt/sources.list"
deb-src $MIRROR $BASESUITE main
END
chdist_base apt-get update

COMMON_SBUILD_OPTS="-d $BASESUITE --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --no-apt-upgrade --no-apt-distupgrade"
COMMON_BUILD_PROFILES="nobiarch,nocheck,noudeb"

for p in patches/*; do
	p=${p#patches/}

	if [ ! -e "patches/$p" ]; then
		echo "patches/$p doesn't exist"
		continue
	fi

	if [ ! -x "patches/$p" ]; then
		echo "patches/$p is not executable"
		continue
	fi

	# shellcheck disable=SC2016
	our_version=$(reprepro --list-format '${version}_${source}\n' -T deb listfilter "$OURSUITE" "\$Source (== $p)" | sed 's/.*_.*(\(.*\))$/\1/;s/_.*//' | uniq)
	their_version=$(chdist_base apt-get source --only-source -t "$BASESUITE" --no-act "$p" | sed "s/^Selected version '\\([^']*\\)' ($BASESUITE) for .*/\\1/;t;d")
	if test -z "$their_version"; then
		echo "cannot determine source version for $p"
		exit 1
	fi
	if test -n "$our_version" && dpkg --compare-versions "$our_version" gt "$their_version"; then
		if [ -e repo/dists/$OURSUITE/Release ] && [ repo/dists/$OURSUITE/Release -ot "patches/$p" ]; then
			echo "patches/$p has been changed -- rebuilding"
		else
			echo "package $p up to date"
			continue
		fi
	fi

	reprepro removesrc "$OURSUITE" "$p"

	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		chdist_base apt-get source --only-source -t "$BASESUITE" "$p"
		cd "$p-"*
		dch --local "+$OURSUITE" "apply mnt reform patch"
		dch --force-distribution --distribution="$OURSUITE" --release ""
		"$PATCHDIR/$p"
		# cross build foreign arch:any packages
		if [ -n "$(env DEB_HOST_ARCH=$HOST_ARCH DEB_BUILD_PROFILES="cross $(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			rm -f ../*.changes
			ret=0
			sbuild --host="$HOST_ARCH" \
				--no-arch-all --arch-any \
				--profiles="cross,$COMMON_BUILD_PROFILES" \
				$COMMON_SBUILD_OPTS \
				--extra-repository="$SRC_LIST_PATCHED" || ret=$?
			if [ "$ret" -ne 0 ]; then
				# cross building failed -- try building
				# "natively" with qemu-user
				sbuild --build="$HOST_ARCH" --host="$HOST_ARCH" \
					--no-arch-all --arch-any \
					--profiles="$COMMON_BUILD_PROFILES" \
					$COMMON_SBUILD_OPTS \
					--extra-repository="$SRC_LIST_PATCHED"
			fi
			reprepro include "$OURSUITE" ../*.changes
		fi
		# natively build arch:all packages and build-arch packages
		# just building arch:all packages is not enough in case later
		# packages need to install native arch versions of m-a:same
		# packages and we need to prevent a version skew
		if [ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="cross $(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -i)" ] \
		|| [ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="cross $(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			rm -f ../*.changes
			sbuild --arch-all --arch-any \
				--profiles="$COMMON_BUILD_PROFILES" \
				$COMMON_SBUILD_OPTS \
				--extra-repository="$SRC_LIST_PATCHED"
			reprepro include "$OURSUITE" ../*.changes
		fi
		cd ..
	)
	rm -Rf "$WORKDIR"
done

if [ -z "$(reprepro listfilter reform "\$Source (== box64)")" ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://salsa.debian.org/debian/box64.git
		cd box64
		git checkout pristine-tar
		git checkout upstream
		git checkout master
		pristine-tar checkout ../box64_0.2.2+dfsg1.orig.tar.xz
		ret=0
		sbuild --host="$HOST_ARCH" --arch-all --arch-any $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED" || ret=$?
		if [ "$ret" -ne 0 ]; then
			# cross building failed -- try building
			# "natively" with qemu-user
			sbuild --build="$HOST_ARCH" --host="$HOST_ARCH" --arch-all --arch-any $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		fi
		reprepro include "$OURSUITE" ../box64_0.2.2+dfsg1-1_arm64.changes
		cd ..
	)
	rm -Rf "$WORKDIR"
fi

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

if [ -z "$(reprepro listfilter reform "Package (== reform-tools)")" ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://source.mnt.re/reform/reform-tools.git
		cd reform-tools
		sbuild --arch-all --arch-any $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		reprepro include "$OURSUITE" ../reform-tools_*_amd64.changes
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
		sbuild --arch-all --arch-any $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		reprepro include "$OURSUITE" ../reform-handbook_*_amd64.changes
		cd ..
	)
	rm -Rf "$WORKDIR"
fi

if [ -z "$(reprepro listfilter reform "\$Source (== linux)")" ]; then
	env --chdir=linux \
		BUILD_ARCH="$BUILD_ARCH" HOST_ARCH="$HOST_ARCH" \
		BASESUITE="$BASESUITE" OURSUITE="$OURSUITE" \
		./build.sh
fi
