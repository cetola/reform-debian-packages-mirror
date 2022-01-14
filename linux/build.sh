#!/bin/sh

set -e
set -u

if [ ! -d linux ]; then
	git clone --depth 1 --branch v5.12 https://github.com/torvalds/linux.git
fi
if [ ! -d packaging ]; then
	git clone --branch=debian/5.13.12-1_exp1 --depth=1 https://salsa.debian.org/kernel-team/linux.git packaging
fi

git -C linux clean -fdx
git -C linux reset --hard

if [ ! -e linux_5.12.orig.tar.gz ]; then
	git -C linux archive --prefix=linux/ HEAD | gzip --to-stdout > linux_5.12.orig.tar.gz
fi

cp -a packaging/debian linux
rm linux/debian/changelog
rm linux/debian/changelog.old

cat << END > linux/debian/changelog
linux (5.12-1~exp1.1) UNRELEASED; urgency=medium

  * Non-maintainer upload.

 -- Johannes Schauer Marin Rodrigues <josch@debian.org>  $(date --rfc-email)
END

env --chdir=linux patch -p1 < packaging.diff

export DEBIAN_KERNEL_DISABLE_DEBUG=1
export DEBIAN_KERNEL_DISABLE_INSTALLER=1
export DEBIAN_KERNEL_DISABLE_SIGNED=1

# this command fails intentionally, so we let it always succeed
make -C linux -f debian/rules debian/control || :

# running the last command creates pyc files that we don't want
rm -r ./linux/debian/lib/python/debian_linux/__pycache__

cp config linux/debian/config/arm64/config

env --chdir=linux patch -p1 < packaging2.diff

mkdir linux/debian/patches/reform
cp patches/* linux/debian/patches/reform

cat << 'END' | env --chdir=linux patch -p1
diff -ru linux/debian/patches/series linux/debian/patches/series
--- linux/debian/patches/series	2022-01-14 07:52:25.468668311 +0100
+++ linux/debian/patches/series	2022-01-13 22:45:13.359057117 +0100
@@ -128,3 +128,18 @@
 bugfix/all/tools-include-uapi-fix-errno.h.patch

 # ABI maintenance
+
+# reform
+reform/0001-nwl-dsi-fixup-mode-only-for-LCDIF-input-not-DCSS.patch
+reform/0005-pci-imx6-add-support-for-internal-refclk-imx8mq.patch
+reform/0009-revert-58074b08c04af1817ab34be986a80279e7267d07-edid.patch
+reform/caam-revert-imx8m-soc-match.patch
+reform/caam-revert-swiotlb-origaddr.patch
+reform/mnt3004-MNT-Reform-imx8mq-add-PHY_27M-clock.patch
+reform/mnt3006-MNT-Reform-imx8mq-add-PHY_27M-clock-missing-define.patch
+reform/mnt4000-limit-fslsai-to-48khz.patch
+reform/mnt4001-lcdif-fix-pcie-interference.patch
+reform/mnt4002-imx-gpcv2-wake-smccc.patch
+reform/mnt4003-emmc-clockgate.patch
+reform/mnt5000-imx8mq-import-HDMI-driver-and-make-DCSS-compatible.patch
+reform/dtb.patch
diff --git a/debian/patches/reform/dtb.patch b/debian/patches/reform/dtb.patch
new file mode 100644
index 000000000000..1d86e1d33dc3
--- /dev/null
+++ b/debian/patches/reform/dtb.patch
@@ -0,0 +1,12 @@
+diff --git a/arch/arm64/boot/dts/freescale/Makefile b/arch/arm64/boot/dts/freescale/Makefile
+index 44890d56c194..e45c8f9c8912 100644
+--- a/arch/arm64/boot/dts/freescale/Makefile
++++ b/arch/arm64/boot/dts/freescale/Makefile
+@@ -51,6 +51,7 @@ dtb-$(CONFIG_ARCH_MXC) += imx8mq-librem5-devkit.dtb
+ dtb-$(CONFIG_ARCH_MXC) += imx8mq-librem5-r2.dtb
+ dtb-$(CONFIG_ARCH_MXC) += imx8mq-librem5-r3.dtb
+ dtb-$(CONFIG_ARCH_MXC) += imx8mq-librem5-r4.dtb
++dtb-$(CONFIG_ARCH_MXC) += imx8mq-mnt-reform2.dtb
+ dtb-$(CONFIG_ARCH_MXC) += imx8mq-nitrogen.dtb
+ dtb-$(CONFIG_ARCH_MXC) += imx8mq-phanbell.dtb
+ dtb-$(CONFIG_ARCH_MXC) += imx8mq-pico-pi.dtb
END

env --chdir=linux QUILT_PATCHES=debian/patches quilt push -a
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2.dts
cp imx8mq-mnt-reform2.dts linux/arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt refresh

env --chdir=linux \
	DEB_BUILD_PROFILES="cross nodoc pkg.linux.nosource pkg.linux.notools" \
	sbuild -d "$BASESUITE" --arch-any --no-arch-all --host="$HOST_ARCH" \
		--nolog --no-source-only-changes --no-run-lintian --no-run-autopkgtest

reprepro include "$OURSUITE" ./linux_5.12-1~exp1.1_arm64.changes
