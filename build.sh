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
SOURCE_DATE_EPOCH=$(date +%s)
export SOURCE_DATE_EPOCH
export REPREPRO_BASE_DIR
HTTPD_PID=

export DEBEMAIL='robot <reform@reform.repo>'

cleanup() {
	if test -n "$HTTPD_PID"; then
		kill "$HTTPD_PID"
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

DEB_BUILD_PROFILES="nobiarch nocheck noudeb nodoc pkg.linux.nosource pkg.linux.notools"
if [ "$BUILD_ARCH" != "$HOST_ARCH" ]; then
	DEB_BUILD_PROFILES="cross $DEB_BUILD_PROFILES"
fi
export DEB_BUILD_PROFILES
export DEB_BUILD_OPTIONS="noautodbgsym nocheck noudeb nodoc"

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
		if [ -n "$(env DEB_HOST_ARCH=$HOST_ARCH dh_listpackages -a)" ]; then
			rm -f ../*.changes
			sbuild -d "$BASESUITE" --host="$HOST_ARCH" --no-arch-all --arch-any --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --extra-repository="$SRC_LIST_PATCHED" --no-apt-upgrade --no-apt-distupgrade
			reprepro include "$OURSUITE" ../*.changes
		fi
		# natively build arch:all packages
		if [ -n "$(env DEB_HOST_ARCH=$HOST_ARCH dh_listpackages -i)" ]; then
			rm -f ../*.changes
			sbuild -d "$BASESUITE" --arch-all --no-arch-any --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --extra-repository="$SRC_LIST_PATCHED" --no-apt-upgrade --no-apt-distupgrade
			reprepro include "$OURSUITE" ../*.changes
		fi
		cd ..
	)
	rm -Rf "$WORKDIR"
done

# starting with 2.80, blender requires 3.2+, so 2.79b is the last one that
# works on reform with imx8mq
if [ -z "$(reprepro listfilter reform "\$Source (== blender)")" ]; then
	env --chdir=blender \
		BUILD_ARCH="$BUILD_ARCH" HOST_ARCH="$HOST_ARCH" \
		BASESUITE="$BASESUITE" OURSUITE="$OURSUITE" \
		./build.sh
fi

if [ -z "$(reprepro listfilter reform "Package (== reform-tools)")" ]; then
	dpkg-deb --root-owner-group --build reform-tools_1.0-7
	reprepro includedeb "$OURSUITE" reform-tools_1.0-7.deb
fi

# https://ftp-master.debian.org/new/neatvnc_0.4.0+dfsg-1.html
if [ -z "$(reprepro listfilter reform "\$Source (== neatvnc)")" ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://salsa.debian.org/debian/neatvnc.git
		cd neatvnc
		git checkout pristine-tar
		git checkout upstream
		git checkout master
		pristine-tar checkout ../neatvnc_0.4.0+dfsg.orig.tar.xz
		sbuild -d "$BASESUITE" --host="$HOST_ARCH" --no-arch-all --arch-any --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --extra-repository="$SRC_LIST_PATCHED" --no-apt-upgrade --no-apt-distupgrade
		reprepro include "$OURSUITE" ../neatvnc_0.4.0+dfsg-1_arm64.changes
		cd ..
	)
	rm -Rf "$WORKDIR"
fi

# https://ftp-master.debian.org/new/wayvnc_0.4.1-1.html
if [ -z "$(reprepro listfilter reform "\$Source (== wayvnc)")" ]; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://salsa.debian.org/debian/wayvnc.git
		cd wayvnc
		git checkout pristine-tar
		git checkout upstream
		git checkout master
		pristine-tar checkout ../wayvnc_0.4.1.orig.tar.gz
		sbuild -d "$BASESUITE" --host="$HOST_ARCH" --no-arch-all --arch-any --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --extra-repository="$SRC_LIST_PATCHED" --no-apt-upgrade --no-apt-distupgrade
		reprepro include "$OURSUITE" ../wayvnc_0.4.1-1_arm64.changes
		cd ..
	)
	rm -Rf "$WORKDIR"
fi
