#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

. ./common.sh

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

	# We print '${version}_${source}\n' and then do sed filtering to get
	# to the version of the source package and discard the (possibly
	# differing) version of the binary packages it builds using sed.
	# shellcheck disable=SC2016
	our_version=$(reprepro --list-format '${version}_${source}\n' -T deb listfilter "$OURSUITE" "\$Source (== $p)" | sed 's/.*_.*(\(.*\))$/\1/;s/_.*//' | uniq)
	their_version=$(chdist_base apt-get source --only-source -t "$BASESUITE" --no-act "$p" | sed "s/^Selected version '\\([^']*\\)' ($BASESUITE) for .*/\\1/;t;d")
	if test -z "$their_version"; then
		echo "W: cannot determine source version for $p -- skipping..." >&2
		continue
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
		dch --local "+$VERSUFFIX" "apply mnt reform patch"
		dch --force-distribution --distribution="$OURSUITE" --release ""
		"$PATCHDIR/$p"
		# cross build foreign arch:any packages
		if [ "$BUILD_ARCH" != "$HOST_ARCH" ] && [ -n "$(env DEB_HOST_ARCH=$HOST_ARCH DEB_BUILD_PROFILES="cross nodoc $(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			rm -f ../*.changes
			ret=0
			sbuild --chroot $BASESUITE-$BUILD_ARCH \
				--host="$HOST_ARCH" \
				--no-arch-all --arch-any \
				--profiles="cross,nodoc,$COMMON_BUILD_PROFILES" \
				$COMMON_SBUILD_OPTS \
				--extra-repository="$SRC_LIST_PATCHED" || ret=$?
			if [ "$ret" -ne 0 ]; then
				# cross building failed -- try building
				# "natively" with qemu-user
				sbuild --chroot $BASESUITE-$HOST_ARCH \
					--build="$HOST_ARCH" --host="$HOST_ARCH" \
					--no-arch-all --arch-any \
					--profiles="$COMMON_BUILD_PROFILES" \
					$COMMON_SBUILD_OPTS \
					--extra-repository="$SRC_LIST_PATCHED"
			fi
			mv -v ../*.changes "../${p}_cross.changes"
			reprepro include "$OURSUITE" "../${p}_cross.changes"
			dcmd mv -v ../*.changes "$ROOTDIR/changes/"
			mv -v ../*_$HOST_ARCH-*.build "$ROOTDIR/buildlogs"
		fi
		# natively build arch:all packages and build-arch packages
		# just building arch:all packages is not enough in case later
		# packages need to install native arch versions of m-a:same
		# packages and we need to prevent a version skew
		if [ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="$(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -i)" ] \
		|| [ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="$(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			rm -f ../*.changes
			sbuild --chroot $BASESUITE-$BUILD_ARCH \
				--arch-all --arch-any \
				--profiles="$COMMON_BUILD_PROFILES" \
				$COMMON_SBUILD_OPTS \
				--extra-repository="$SRC_LIST_PATCHED"
			mv -v ../*.changes "../${p}_native.changes"
			reprepro include "$OURSUITE" "../${p}_native.changes"
			dcmd mv -v ../*.changes "$ROOTDIR/changes/"
			mv -v ../*_$BUILD_ARCH-*.build "$ROOTDIR/buildlogs"
		fi
		cd ..
	)
	rm -Rf "$WORKDIR"
done
