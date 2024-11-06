#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

. ./common.sh


if [ ! -e fonts-reform-iosevka-term_2.3.0-1_all.deb ]; then
	if [ ! -e 02-iosevka-term-2.3.0.zip ]; then
		curl --location --remote-name https://github.com/be5invis/Iosevka/releases/download/v2.3.0/02-iosevka-term-2.3.0.zip
	fi
	echo "ce6d0b566f217fd7b778689f388c9973e3914d94  02-iosevka-term-2.3.0.zip" | sha1sum --check
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	mkdir -p "$WORKDIR/02-iosevka-term-2.3.0"
	unzip -d "$WORKDIR/02-iosevka-term-2.3.0" -x 02-iosevka-term-2.3.0.zip
	rm -r "$WORKDIR/02-iosevka-term-2.3.0/ttf-unhinted"
	rm -r "$WORKDIR/02-iosevka-term-2.3.0/woff"
	rm -r "$WORKDIR/02-iosevka-term-2.3.0/woff2"
	rm -r "$WORKDIR/02-iosevka-term-2.3.0/iosevka-term-regular.charmap"
	rm -r "$WORKDIR/02-iosevka-term-2.3.0/webfont.css"
	mkdir -p "$WORKDIR/usr/share/fonts/truetype/"
	mv "$WORKDIR/02-iosevka-term-2.3.0/ttf" "$WORKDIR/usr/share/fonts/truetype/Iosevka Term"
	rmdir "$WORKDIR/02-iosevka-term-2.3.0"
	mkdir "$WORKDIR/DEBIAN"
	cat << 'END' > "$WORKDIR/DEBIAN/control"
Package: fonts-reform-iosevka-term
Version: 2.3.0-1
Section: fonts
Priority: optional
Architecture: all
Multi-Arch: foreign
Maintainer: Lukas F. Hartmann <lukas@mntre.com>
Description: Versatile typeface for code, from code
 Iosevka [ˌjɔˈseβ.kʰa] is an open-source, sans-serif + slab-serif, monospace +
 quasi‑proportional typeface family, designed for writing code, using in
 terminals, and preparing technical documents.
 .
 This package provides the "Term" subfamily of Iosevka as ttf.
END
	dpkg-deb --root-owner-group --build "$WORKDIR" .
	rm -Rf "$WORKDIR"
fi

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

# use the version of reform-handbook as it was uploaded to the NEW queue
for f in "all.deb" "arm64.buildinfo" "arm64.changes"; do
  curl --remote-name --remote-header-name --location "https://mister-muffin.de/reform/reform-handbook/reform-handbook_2024-08-19+dfsg-1_$f"
done
cat << END | sha1sum --check
eb6133aafa05e7a5b099c3303322d8a065b57037  reform-handbook_2024-08-19+dfsg-1_all.deb
aa40d9601eac4d4901e475f1e54788c746aba6f9  reform-handbook_2024-08-19+dfsg-1_arm64.buildinfo
146de4bf02b6a819137508cce399c4d3889b7459  reform-handbook_2024-08-19+dfsg-1_arm64.changes
END
sed -i "s/^Distribution: unstable\$/Distribution: $OURSUITE/" "reform-handbook_2024-08-19+dfsg-1_arm64.changes"
dcmd mv -v reform-handbook_2024-08-19+dfsg-1_arm64.changes "$ROOTDIR/changes"

for HB in pocket-reform-handbook; do
our_version=$(reprepro --list-format '${version}\n' -T deb listfilter "$OURSUITE" "\$Source (== $HB)" | uniq)
their_version=$(curl --silent "https://source.mnt.re/reform/$HB/-/raw/main/debian/changelog" | dpkg-parsechangelog --show-field Version --file -)
if [ -z "$our_version" ] || dpkg --compare-versions "$our_version" lt "$their_version"; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone "https://source.mnt.re/reform/$HB.git"
		cd "$HB"
		sbuild -d "$OURSUITE" --arch-all --arch-any --chroot "$BASESUITE-$BUILD_ARCH" $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		dcmd mv -v "../${HB}_"*"_${BUILD_ARCH}.changes" "$ROOTDIR/changes"
		cd ..
	)
	rm -Rf "$WORKDIR"
fi
done

our_version=$(reprepro --list-format '${version}\n' -T deb listfilter "$OURSUITE" "\$Source (== reform-branding)" | uniq)
their_version=$(curl --silent https://salsa.debian.org/reform-team/reform-branding/-/raw/main/debian/changelog | dpkg-parsechangelog --show-field Version --file -)
if [ -z "$our_version" ] || dpkg --compare-versions "$our_version" lt "$their_version"; then
	rm -Rf "$WORKDIR"
	mkdir --mode=0777 "$WORKDIR"
	(
		cd "$WORKDIR"
		git clone https://salsa.debian.org/reform-team/reform-branding.git
		cd reform-branding
		sbuild -d "$OURSUITE" --arch-all --arch-any --chroot $BASESUITE-$BUILD_ARCH $COMMON_SBUILD_OPTS --extra-repository="$SRC_LIST_PATCHED"
		dcmd mv -v ../reform-branding_*"_${BUILD_ARCH}.changes" "$ROOTDIR/changes"
		cd ..
	)
	rm -Rf "$WORKDIR"
fi
