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

	# if we are in a git repository, set SOURCE_DATE_EPOCH to the timestamp of
	# the latest change to the patch
	if git -C . rev-parse 2>/dev/null; then
		# reform-tools is special because its changes depend on the contents of the
		# ./reform-tools directory but only if we we are building for the suite
		# "reform"
		if [ "$OURSUITE" = "reform" ] && [ "$p" = "reform-tools" ]; then
			SOURCE_DATE_EPOCH=$(git log -1 --format=%ct -- "./reform-tools")
		else
			SOURCE_DATE_EPOCH=$(git log -1 --format=%ct -- "./patches/$p")
		fi
	fi
	datesuffix="$(date --utc --date=@$SOURCE_DATE_EPOCH +%Y%m%dT%H%M%SZ)"
	case "$OURSUITE" in
	bookworm-backports) datesuffix="$datesuffix~bpo12" ;;
	trixie-backports) datesuffix="$datesuffix~bpo13" ;;
	esac

	# We print '${version}_${source}\n' and then do sed filtering to get
	# to the version of the source package and discard the (possibly
	# differing) version of the binary packages it builds using sed.
	# shellcheck disable=SC2016
	our_version=$(reprepro --list-format '${version}_${source}\n' -T deb listfilter "$OURSUITE" "\$Source (== $p)" | sed 's/.*_.*(\(.*\))$/\1/;s/_.*//' | uniq)
	OUR_BASESUITE=$BASESUITE
	their_version=$(chdist_base apt-get source --only-source -t "$OUR_BASESUITE" --no-act "$p" | sed "s/^Selected version '\\([^']*\\)' ($OUR_BASESUITE) for .*/\\1/;t;d")
	if test -z "$their_version" && [ "$OUR_BASESUITE" = "experimental" ]; then
		# if the package was not in experimental, try again with unstable
		echo "I: package was not found in experimental, trying again with unstable" >&2
		OUR_BASESUITE=unstable
		their_version=$(chdist_base apt-get source --only-source -t "$OUR_BASESUITE" --no-act "$p" | sed "s/^Selected version '\\([^']*\\)' ($OUR_BASESUITE) for .*/\\1/;t;d")
	fi
	if test -z "$their_version"; then
		echo "E: cannot determine source version for $p" >&2
		exit 1
	fi
	if test -n "$our_version" && dpkg --compare-versions "$our_version" gt "$their_version"; then
		our_suffix=${our_version#*"+$VERSUFFIX"}
		# strip off the "1" which got added by dch --local and the "+" which was
		# added by us
		our_suffix=${our_suffix%+1}
		# strip off the ~bpo suffix for backports
		case "$OURSUITE" in
		bookworm-backports) our_suffix=${our_suffix%~bpo12} ;;
		trixie-backports) our_suffix=${our_suffix%~bpo13} ;;
		esac
		case $our_suffix in
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) : ;;
		*)
			echo "E: unknown format in date suffix: $our_suffix" >&2
			exit 1
			;;
		esac
		if dpkg --compare-versions "$datesuffix" gt "$our_suffix"; then
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
		chdist_base apt-get source --only-source -t "$OUR_BASESUITE" "$p"
		cd "$p-"*
		# dch --local adds a "1" to the version, so separate it with a "+"
		dch --local "+$VERSUFFIX$datesuffix+" "apply mnt reform patch"
		dch --date="$(date --utc --date=@$SOURCE_DATE_EPOCH --rfc-email)" --force-distribution --distribution="$OURSUITE" --release ""
		"$PATCHDIR/$p"
		# cross build foreign arch:any packages
		if [ "$BUILD_ARCH" != "$HOST_ARCH" ] && [ -n "$(env DEB_HOST_ARCH=$HOST_ARCH DEB_BUILD_PROFILES="cross nodoc $(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			rm -f ../*.changes
			ret=0
			sbuild --chroot $OUR_BASESUITE-$BUILD_ARCH \
				--host="$HOST_ARCH" \
				--no-arch-all --arch-any \
				--profiles="cross,nodoc,$COMMON_BUILD_PROFILES" \
				$COMMON_SBUILD_OPTS \
				--extra-repository="$SRC_LIST_PATCHED" || ret=$?
			if [ "$ret" -ne 0 ]; then
				# cross building failed -- try building
				# "natively" with qemu-user
				sbuild --chroot $OUR_BASESUITE-$HOST_ARCH \
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
		if [ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="$(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -i)" ] ||
			[ -n "$(env DEB_HOST_ARCH=$BUILD_ARCH DEB_BUILD_PROFILES="$(echo $COMMON_BUILD_PROFILES | tr ',' ' ')" dh_listpackages -a)" ]; then
			rm -f ../*.changes
			sbuild --chroot $OUR_BASESUITE-$BUILD_ARCH \
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
