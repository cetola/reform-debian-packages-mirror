#!/bin/sh

set -e
set -u
set -x

if [ ! -d linux ]; then
	git clone --branch=master --depth=1 https://salsa.debian.org/kernel-team/linux.git linux
fi

git -C linux clean -fdx
git -C linux reset --hard

env --chdir=linux dch --local "+$OURSUITE" "apply mnt reform patch"
env --chdir=linux dch --force-distribution --distribution="$OURSUITE" --release ""

env --chdir=linux patch -p1 < packaging.diff

# use sed to change abiname to avoid the patch not working on any abi bump
sed --in-place --expression 's/^abiname: \([0-9]\+\|trunk\)$/abiname: reform2/' linux/debian/config/defines
grep --quiet '^abiname: reform2$' linux/debian/config/defines

if [ ! -e orig ]; then
	env --chdir=linux debian/bin/genorig.py https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
fi

export DEBIAN_KERNEL_DISABLE_DEBUG=1
export DEBIAN_KERNEL_DISABLE_INSTALLER=1
export DEBIAN_KERNEL_DISABLE_SIGNED=1

make -C linux -f debian/rules orig

# this command fails intentionally, so we let it always succeed
make -C linux -f debian/rules debian/control || :

# running the last command creates pyc files that we don't want
rm -r ./linux/debian/lib/python/debian_linux/__pycache__

cp config linux/debian/config/arm64/config


mkdir linux/debian/patches/reform
cp patches/* linux/debian/patches/reform

cat << 'END' | env --chdir=linux patch -p1
diff -ru linux/debian/patches/series linux/debian/patches/series
--- linux/debian/patches/series	2022-01-14 07:52:25.468668311 +0100
+++ linux/debian/patches/series	2022-01-13 22:45:13.359057117 +0100
@@ -128,3 +128,12 @@
 bugfix/all/tools-include-uapi-fix-errno.h.patch

 # ABI maintenance
+
+# reform
+reform/0001-nwl-dsi-fixup-mode-only-for-LCDIF-input-not-DCSS.patch
+reform/0005-pci-imx6-add-support-for-internal-refclk-imx8mq.patch
+reform/mnt3004-MNT-Reform-imx8mq-add-PHY_27M-clock.patch
+reform/mnt3006-MNT-Reform-imx8mq-add-PHY_27M-clock-missing-define.patch
+reform/mnt4001-lcdif-fix-pcie-interference.patch
+reform/mnt4002-imx-gpcv2-wake-smccc.patch
+reform/mnt5000-imx8mq-import-HDMI-driver-and-make-DCSS-compatible.patch
END

env --chdir=linux QUILT_PATCHES=debian/patches quilt push -a
env --chdir=linux QUILT_PATCHES=debian/patches quilt new reform/dts.patch
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2.dts
cp imx8mq-mnt-reform2.dts linux/arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2-hdmi.dts
cp imx8mq-mnt-reform2-hdmi.dts linux/arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2-hdmi.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/Makefile
sed -i '/imx8mq-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_MXC) += imx8mq-mnt-reform2-hdmi.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
env --chdir=linux QUILT_PATCHES=debian/patches quilt refresh

env --chdir=linux \
	DEB_BUILD_PROFILES="cross nodoc pkg.linux.nosource pkg.linux.notools" \
	sbuild -d "$BASESUITE" --arch-any --no-arch-all --host="$HOST_ARCH" \
		--pre-build-commands '%SBUILD_CHROOT_EXEC sh -c "mkdir -p /usr/lib/apt/solvers"' \
		--pre-build-commands 'cat /usr/lib/apt/solvers/apt | %SBUILD_CHROOT_EXEC sh -c "cat > /usr/lib/apt/solvers/apt"' \
		--pre-build-commands '%SBUILD_CHROOT_EXEC sh -c "chmod +x /usr/lib/apt/solvers/apt"' \
		--pre-build-commands 'cat /usr/lib/apt/solvers/sbuild-cross-resolver | %SBUILD_CHROOT_EXEC sh -c "cat > /usr/lib/apt/solvers/sbuild-cross-resolver"' \
		--pre-build-commands '%SBUILD_CHROOT_EXEC sh -c "chmod +x /usr/lib/apt/solvers/sbuild-cross-resolver"' \
		--nolog --no-source-only-changes --no-run-lintian --no-run-autopkgtest

reprepro include "$OURSUITE" ./linux_5.17~rc2-1~exp1.1_arm64.changes
