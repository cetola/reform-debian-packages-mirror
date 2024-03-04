#!/bin/sh
#
# Why do we build the kernel as a Debian package instead of straight from
# kernel.org git:
#
#  - allow upgrading the kernel via 'apt upgrade'
#  - system is closer to a 'real Debian' so that no special knowledge is needed
#  - integration with flash-kernel and update-initramfs
#  - allows building kernel modules like zfs-dkms via linux-kbuild & linux-headers
#  - allows features like supermin+guestfs or anbox
#  - support for all hardware that Debian supports via modules
#  - minimize the diff so that reform support can be added to the official packaging

set -e
set -u
set -x

chdistdata=$(pwd)/../chdist
chdist_base() {
	local cmd
	cmd=$1
	shift
	chdist "--data-dir=$chdistdata" "$cmd" base "$@"
}

USE_GIT=false

if $USE_GIT; then
	if [ ! -d linux ]; then
		git clone --branch=master --depth=1 https://salsa.debian.org/kernel-team/linux.git linux
	fi

	git -C linux clean -fdx
	git -C linux reset --hard

else
	rm -rf linux_*.dsc linux
	chdist_base apt-get source --only-source --download-only -t "$BASESUITE" linux
	dpkg-source -x linux_*.dsc linux
fi

# we add a suffix based on SOURCE_DATE_EPOCH if it is set or "now" otherwise
datesuffix="$(date --utc ${SOURCE_DATE_EPOCH:+--date=@$SOURCE_DATE_EPOCH} +%Y%m%dT%H%M%SZ)"
faketime=
# if we have the faketime utility and if SOURCE_DATE_EPOCH is set, set a
# reproducible d/changelog timestamp using faketime
if command -v faketime >/dev/null && [ -n "${SOURCE_DATE_EPOCH:+x}" ]; then
	faketime="faketime @$SOURCE_DATE_EPOCH"
fi

DEB_VERSION="$(dpkg-parsechangelog --show-field Version --file linux/debian/changelog)"
DEB_VERSION_UPSTREAM="$(echo "$DEB_VERSION" | sed -e 's/-[^-]*$//')"
KVER=$(echo "$DEB_VERSION" | sed 's/\([0-9]\+\.[0-9]\+\).*/\1/')
if dpkg --compare-versions "$KVER" ge "6.7"; then
	oldversion="$(dpkg-parsechangelog --show-field=Version --file linux/debian/changelog)"
	newversion="$(echo "$oldversion" | sed 's/\([0-9.]\+\)\(.*\)/\1-reform2\2/')"
	env --chdir=linux TZ=UTC $faketime dch --newversion "$newversion+$VERSUFFIX$datesuffix" "apply mnt reform patch"
	mv "linux_$DEB_VERSION_UPSTREAM.orig.tar.xz" "linux_$DEB_VERSION_UPSTREAM-reform2.orig.tar.xz"
else
	env --chdir=linux TZ=UTC $faketime dch --local "+$VERSUFFIX$datesuffix" "apply mnt reform patch"
fi
env --chdir=linux TZ=UTC $faketime dch --force-distribution --distribution="$OURSUITE" --release ""

env --chdir=linux patch -p1 < packaging.diff

# new toml config format since 6.7
if dpkg --compare-versions "$KVER" ge "6.7"; then
	mkdir -p linux/debian/config.local/arm64
	cat << END >> linux/debian/config.local/arm64/defines.toml
[[flavour]]
name = 'arm64'
[flavour.defs]
is_default = true
[flavour.packages]
installer = false
docs = false

[[featureset]]
name = 'none'

[[featureset.flavour]]
name = 'arm64'

[build]
enable_signed = false
END
else
	mkdir -p linux/debian/config.local/arm64/none
	cat << END >> linux/debian/config.local/defines
[packages]
installer: false
docs: false
END
	cat << END >> linux/debian/config.local/arm64/defines
[base]
featuresets: none

[build]
signed-code: false
END
	cat << END >> linux/debian/config.local/arm64/none/defines
[base]
flavours: arm64
END
fi

KVER=$(dpkg-parsechangelog --show-field Version --file linux/debian/changelog | sed 's/\([0-9]\+\.[0-9]\+\).*/\1/')

# the abiname field was dropped in 6.6 with commit 3282bf29846a0c47a8e01c60c038d29ad17c573d
# since 6.7 there is the new toml config format
if dpkg --compare-versions "$KVER" ge "6.7"; then
	: # nothing to do
elif test "$KVER" = 6.6; then
	# apply https://salsa.debian.org/kernel-team/linux/-/merge_requests/957
	cat << END | env --chdir=linux patch -p1
--- a/debian/bin/gencontrol.py
+++ b/debian/bin/gencontrol.py
@@ -640,6 +640,9 @@ linux-signed-{vars['arch']} (@signedtemplate_sourceversion@) {dist}; urgency={ur
         else:
             self.abiname = f'{version.linux_upstream_full}'

+        if 'abisuffix' in self.config.get(('abi',), {}):
+            self.abiname += self.config['abi', ]['abisuffix']
+
         self.vars = {
             'upstreamversion': self.version.linux_upstream,
             'version': self.version.linux_version,
END
	cat << END >> linux/debian/config.local/defines

[abi]
abisuffix: -reform2
END
else
	# use sed to change abiname to avoid the patch not working on any abi bump
	sed --in-place --expression 's/^abiname: \([0-9]\+\|trunk\|[0-9]\+\.deb[0-9.]\+\)$/abiname: \1-reform2/' linux/debian/config/defines
	grep --quiet '^abiname: [0-9a-z.]\+-reform2$' linux/debian/config/defines
fi

export DEBIAN_KERNEL_DISABLE_DEBUG=1
export DEBIAN_KERNEL_DISABLE_INSTALLER=1
export DEBIAN_KERNEL_DISABLE_SIGNED=1

if $USE_GIT; then
	if [ ! -e orig ]; then
		env --chdir=linux debian/bin/genorig.py https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
	fi

	make -C linux -f debian/rules orig
fi

# this command fails intentionally, so we let it always succeed
make -C linux -f debian/rules debian/control-real && exit 1 || :

# running the last command creates pyc files that we don't want
rm -r ./linux/debian/lib/python/debian_linux/__pycache__

if [ ! -d kernel-team ]; then
	git clone https://salsa.debian.org/kernel-team/kernel-team.git
fi
cat config >> linux/debian/config/arm64/config
env --chdir=linux debian/rules source
env --chdir=linux ../kernel-team/utils/kconfigeditor2/process.py .

if [ ! -e "patches${KVER}" ]; then
	echo "no patches for linux $KVER prepared yet" >&2
	exit 1
fi

mkdir linux/debian/patches/reform
cp -a "patches${KVER}"/* linux/debian/patches/reform

find "patches${KVER}/" -type f -name "*.patch" | sort | sed 's/^patches'"$KVER"'\//reform\//' >> linux/debian/patches/series

env --chdir=linux QUILT_PATCHES=debian/patches quilt push -a
env --chdir=linux QUILT_PATCHES=debian/patches quilt new reform/dts.patch
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/fsl-ls1028a-mnt-reform2.dts
cp fsl-ls1028a-mnt-reform2.dts linux/arch/arm64/boot/dts/freescale/fsl-ls1028a-mnt-reform2.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2.dts
cp imx8mq-mnt-reform2.dts linux/arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2-hdmi.dts
cp imx8mq-mnt-reform2-hdmi.dts linux/arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2-hdmi.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/Makefile
sed -i '/fsl-ls1028a-rdb.dtb/a dtb-$(CONFIG_ARCH_LAYERSCAPE) += fsl-ls1028a-mnt-reform2.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
sed -i '/imx8mq-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_MXC) += imx8mq-mnt-reform2-hdmi.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
# pocket reform and a311d only work with 6.5 or later
if dpkg --compare-versions "$KVER" ge "6.5"; then
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mp-mnt-pocket-reform.dts
	cp imx8mp-mnt-pocket-reform.dts linux/arch/arm64/boot/dts/freescale/imx8mp-mnt-pocket-reform.dts
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/amlogic/meson-g12b-bananapi-cm4-mnt-reform2.dts
	cp meson-g12b-bananapi-cm4-mnt-reform2.dts linux/arch/arm64/boot/dts/amlogic/meson-g12b-bananapi-cm4-mnt-reform2.dts
	sed -i '/imx8mq-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_MXC) += imx8mp-mnt-pocket-reform.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
fi
env --chdir=linux QUILT_PATCHES=debian/patches quilt refresh

DEB_BUILD_PROFILES="nodoc pkg.linux.nokerneldbg pkg.linux.nokerneldbginfo"
if [ "$BUILD_ARCH" != "$HOST_ARCH" ]; then
	DEB_BUILD_PROFILES="cross $DEB_BUILD_PROFILES"
fi

env --chdir=linux DEB_BUILD_PROFILES="$DEB_BUILD_PROFILES" \
	sbuild --chroot="$BASESUITE-$BUILD_ARCH" --arch-any --arch-all --host="$HOST_ARCH" \
		--verbose --no-source-only-changes --no-run-lintian --no-run-autopkgtest

mv "./linux_$(dpkg-parsechangelog --show-field Version --file linux/debian/changelog)_arm64.changes" "./linux.changes"
dcmd mv "./linux.changes" "$ROOTDIR/changes"
