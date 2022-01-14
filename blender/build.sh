#!/bin/sh

set -e
set -u

# starting with 2.80, blender requires 3.2+, so 2.79b is the last one that
# works on reform with imx8mq
blenderpatch=$(realpath blender.debdiff)
WORKDIR=$(mktemp -d)
rm -Rf "$WORKDIR"
mkdir --mode=0777 "$WORKDIR"
(
	cd "$WORKDIR"
	dget http://snapshot.debian.org/archive/debian/20190424T035015Z/pool/main/b/blender/blender_2.79.b%2Bdfsg0-7.dsc
	cd blender-2.79.b+dfsg0
	patch -p1 < "$blenderpatch"
	if [ "$BUILD_ARCH" = "$HOST_ARCH" ]; then
		# build everything natively
		sbuild -d "$BASESUITE" --arch-any --arch-all --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --no-apt-upgrade --no-apt-distupgrade
		reprepro include "$OURSUITE" ../blender_2.79.b+dfsg0-7+reform1_arm64.changes
	else
		# cross build arch:any
		sbuild -d "$BASESUITE" --host="$HOST_ARCH" --arch-any --no-arch-all --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --no-apt-upgrade --no-apt-distupgrade
		# native build arch:all
		sbuild -d "$BASESUITE" --no-arch-any --arch-all --nolog --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --no-apt-upgrade --no-apt-distupgrade
		reprepro include "$OURSUITE" ../blender_2.79.b+dfsg0-7+reform1_arm64.changes
		reprepro include "$OURSUITE" ../blender_2.79.b+dfsg0-7+reform1_all.changes
	fi
)
rm -Rf "$WORKDIR"
