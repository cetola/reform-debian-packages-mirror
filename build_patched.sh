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

	# if we are in a git repository, set SOURCE_DATE_EPOCH to the timestamp of
	# the latest change to the patch
	datesuffix=
	if git -C . rev-parse 2>/dev/null; then
		# The date suffix based on the last modification of the patch is an attempt
		# at bumping the package version when the underlying patch changes. In
		# practice, every rebuild can change the package when build dependencies
		# change. It would thus be "safer" (avoid different hashes for the same
		# version) to *always* bump the version on each rebuild. We don't do this
		# as a compromise. Bumping the version too often is also disruptive on
		# user's platforms due to long kernel installation times (initramfs, dkms)
		# and large download size etc...
		SOURCE_DATE_EPOCH=$(git log -1 --format=%ct "patches/$p")
		datesuffix="$(date --utc --date=@$SOURCE_DATE_EPOCH +%Y%m%dT%H%M%SZ)"
	fi

	reprepro removesrc "$OURSUITE" "$p"

	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		chdist_base apt-get source --only-source -t "$BASESUITE" "$p"
		cd "$p-"*
		dch --local "+$VERSUFFIX$datesuffix" "apply mnt reform patch"
		dch --date="$(date --utc --date=@$SOURCE_DATE_EPOCH --rfc-email)" --force-distribution --distribution="$OURSUITE" --release ""
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
		# if arm64 is *not* the host arch and if the package only builds
		# arch:all packages, then nothing is to be done
		if [ "$HOST_ARCH" != "arm64" ] && [ -z "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="$(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			continue
		fi
		# natively build arch:all packages and build-arch packages
		# just building arch:all packages is not enough in case later
		# packages need to install native arch versions of m-a:same
		# packages and we need to prevent a version skew
		if [ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="$(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -i)" ] \
		|| [ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="$(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			rm -f ../*.changes
			sbuild --chroot $BASESUITE-$BUILD_ARCH \
				--build="$BUILD_ARCH" --host="$BUILD_ARCH" \
				"$([ "$HOST_ARCH" = "arm64" ] && echo --arch-all || echo --no-arch-all)" \
				--arch-any \
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
