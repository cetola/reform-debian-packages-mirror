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
#
# shellcheck disable=SC2016

set -e
set -u
set -x

chdistdata=$(pwd)/../chdist
chdist_base() {
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
	if [ -d linux ]; then
		rm -r linux
	fi
	rm -r "$WORKDIR"
	mkdir -p "$WORKDIR"
	# we cannot use env --chdir=... because chdist_base is a shell function
	cd "$WORKDIR"
	chdist_base apt-get source --only-source --download-only -t "$BASESUITE" linux
	cd -
	dpkg-source -x "$WORKDIR"/linux_*.dsc linux
	rm -r "$WORKDIR"
fi

# we add a suffix based on SOURCE_DATE_EPOCH if it is set or "now" otherwise
datesuffix="$(date --utc ${SOURCE_DATE_EPOCH:+--date=@$SOURCE_DATE_EPOCH} +%Y%m%dT%H%M%SZ)"

# if we have the faketime utility and if SOURCE_DATE_EPOCH is set, set a
# reproducible d/changelog timestamp using faketime
maybe_faketime () {
	if command -v faketime >/dev/null && [ -n "${SOURCE_DATE_EPOCH:+x}" ]; then
		env --chdir=linux TZ=UTC faketime "@$SOURCE_DATE_EPOCH" "$@"
	else
		env --chdir=linux TZ=UTC "$@"
	fi
}

DEB_VERSION="$(dpkg-parsechangelog --show-field Version --file linux/debian/changelog)"
DEB_VERSION_UPSTREAM="$(echo "$DEB_VERSION" | sed -e 's/-[^-]*$//')"
KVER=$(echo "$DEB_VERSION" | sed 's/\([0-9]\+\.[0-9]\+\).*/\1/')
if dpkg --compare-versions "$KVER" ge "6.8"; then
	# Starting with kernel 6.8 we use the flavour name instead of the
	# upstream version to indicate that this is the reform kernel, so
	# we don't need to replace versions and move orig tarballs but
	# just append a suffix to the version.
	# VERSUFFIX is set in common.sh and "reform" by default.
	maybe_faketime dch --newversion "$DEB_VERSION+$VERSUFFIX$datesuffix" "apply mnt reform patch"
elif dpkg --compare-versions "$KVER" ge "6.7"; then
	oldversion="$(dpkg-parsechangelog --show-field=Version --file linux/debian/changelog)"
	newversion="$(echo "$oldversion" | sed 's/\([0-9.]\+\)\(.*\)/\1-reform2\2/')"
	maybe_faketime dch --newversion "$newversion+$VERSUFFIX$datesuffix" "apply mnt reform patch"
	mv "linux_$DEB_VERSION_UPSTREAM.orig.tar.xz" "linux_$DEB_VERSION_UPSTREAM-reform2.orig.tar.xz"
else
	maybe_faketime dch --local "+$VERSUFFIX$datesuffix" "apply mnt reform patch"
fi
maybe_faketime dch --force-distribution --distribution="$OURSUITE" --release ""

# https://salsa.debian.org/kernel-team/linux/-/merge_requests/1493
cat << 'END' | env --chdir=linux patch -p1
diff --git a/debian/templates/headers.control.in b/debian/templates/headers.control.in
index ab1439820ebb..97be1ead1601 100644
--- a/debian/templates/headers.control.in
+++ b/debian/templates/headers.control.in
@@ -2,6 +2,7 @@ Package: linux-headers-@abiname@@localversion@
 Meta-Rules-Target: headers
 Build-Profiles: <!pkg.linux.nokernel>
 Depends:
+ linux-base (>= 4.11+reform20250503),
  linux-headers-@abiname@-common@localversion_headers@ (= ${source:Version}),
  linux-image-@abiname@@localversion@ (= ${binary:Version}) | linux-image-@abiname@@localversion@-unsigned (= ${binary:Version}),
  linux-kbuild-@abiname@,
diff --git a/debian/templates/headers.postinst.in b/debian/templates/headers.postinst.in
index c13e6dc54e41..433571b3c1b9 100644
--- a/debian/templates/headers.postinst.in
+++ b/debian/templates/headers.postinst.in
@@ -1,18 +1,7 @@
-#!/usr/bin/perl
-# Author: Michael Gilbert <michael.s.gilbert@gmail.com>
-# Origin: Stripped down version of the linux-headers postinst from Ubuntu's
-#         2.6.32-14-generic kernel, which was itself derived from a
-#         Debian linux-image postinst script.
+#!/bin/sh -e

-$|=1;
-my $version  = "@abiname@@localversion@";
+version=@abiname@@localversion@

-if (-d "/etc/kernel/header_postinst.d") {
-  system ("run-parts --report --exit-on-error --arg=$version " .
-          "/etc/kernel/header_postinst.d") &&
-            die "Failed to process /etc/kernel/header_postinst.d";
-}
+linux-run-hooks headers_postinst "$*" $version

-exit 0;
-
-__END__
+exit 0
diff --git a/debian/templates/image.control.in b/debian/templates/image.control.in
index 8bc561c941dc..1585ca21beeb 100644
--- a/debian/templates/image.control.in
+++ b/debian/templates/image.control.in
@@ -6,7 +6,8 @@ Build-Depends:
  kernel-wedge (>= 2.105~),
 # used by kernel-wedge (only on Linux, thus not declared as a dependency)
  kmod,
-Depends: kmod, linux-base (>= 4.3~), ${misc:Depends}
+Pre-Depends: linux-base (>= 4.11+reform20250503)
+Depends: kmod, ${misc:Depends}
 Suggests: firmware-linux-free, linux-doc-@version@, debian-kernel-handbook
 Description: Linux @upstreamversion@ for @class@
  The Linux kernel @upstreamversion@ and modules for use on @longclass@.
diff --git a/debian/templates/image.postinst.in b/debian/templates/image.postinst.in
index 25e7dd65467e..e62d8655195d 100644
--- a/debian/templates/image.postinst.in
+++ b/debian/templates/image.postinst.in
@@ -17,9 +17,6 @@ fi
 linux-update-symlinks $change $version $image_path
 rm -f /lib/modules/$version/.fresh-install

-if [ -d /etc/kernel/postinst.d ]; then
-    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \
-	      --arg=$image_path /etc/kernel/postinst.d
-fi
+linux-run-hooks postinst "$*" $version $image_path

 exit 0
diff --git a/debian/templates/image.postrm.in b/debian/templates/image.postrm.in
index 3fb22e6d7009..2ca7e5b8b2ca 100644
--- a/debian/templates/image.postrm.in
+++ b/debian/templates/image.postrm.in
@@ -9,9 +9,10 @@ if [ "$1" != upgrade ] && command -v linux-update-symlinks >/dev/null; then
     linux-update-symlinks remove $version $image_path
 fi

-if [ -d /etc/kernel/postrm.d ]; then
-    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \
-	      --arg=$image_path /etc/kernel/postrm.d
+if command -v linux-run-hooks >/dev/null; then
+    linux-run-hooks postrm "$*" $version $image_path
+else
+    echo >&2 'W: linux-base is not installed; cannot run postrm hooks'
 fi

 if [ "$1" = purge ]; then
diff --git a/debian/templates/image.preinst.in b/debian/templates/image.preinst.in
index 8a5658ecd1bb..25173feecc69 100644
--- a/debian/templates/image.preinst.in
+++ b/debian/templates/image.preinst.in
@@ -13,9 +13,6 @@ if [ "$1" = install ]; then
     touch /lib/modules/$version/.fresh-install
 fi

-if [ -d /etc/kernel/preinst.d ]; then
-    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \
-	      --arg=$image_path /etc/kernel/preinst.d
-fi
+linux-run-hooks preinst "$*" $version $image_path

 exit 0
diff --git a/debian/templates/image.prerm.in b/debian/templates/image.prerm.in
index f1bde29b1151..eb3cccadf85c 100644
--- a/debian/templates/image.prerm.in
+++ b/debian/templates/image.prerm.in
@@ -9,9 +9,6 @@ fi

 linux-check-removal $version

-if [ -d /etc/kernel/prerm.d ]; then
-    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \
-	      --arg=$image_path /etc/kernel/prerm.d
-fi
+linux-run-hooks prerm "$*" $version $image_path

 exit 0
--
GitLab
END

if [ "$KVER" = "6.11" ]; then
  # see https://salsa.debian.org/kernel-team/linux/-/merge_requests/1260
  cat << 'END' | env --chdir=linux patch -p1
--- a/debian/patches/debian/fixdep-allow-overriding-hostcc-and-hostld.patch
+++ b/debian/patches/debian/fixdep-allow-overriding-hostcc-and-hostld.patch
@@ -18,7 +18,7 @@ override HOSTCC and HOSTLD for fixdep only.
  fixdep:
 -	$(SILENT_MAKE) -C $(srctree)/tools/build $(OUTPUT)fixdep
 +	$(SILENT_MAKE) -C $(srctree)/tools/build \
-+		$(if $(REALHOSTCC),HOSTCC=$(REALHOSTCC) HOSTCFLAGS=) \
++		$(if $(REALHOSTCC),HOSTCC=$(REALHOSTCC) KBUILD_HOSTCFLAGS=) \
 +		$(if $(REALHOSTLD),HOSTLD=$(REALHOSTLD) KBUILD_HOSTLDFLAGS=) \
 +		$(OUTPUT)fixdep
  
END
  # the patch above changed a quilt patch, so we have to adjust the unpacked
  # files to the new reality the patch stack advertises
  cat << 'END' | env --chdir=linux patch -p1
--- a/tools/build/Makefile.include
+++ b/tools/build/Makefile.include
@@ -13,7 +13,7 @@ endif

 fixdep:
 	$(SILENT_MAKE) -C $(srctree)/tools/build \
-		$(if $(REALHOSTCC),HOSTCC=$(REALHOSTCC) HOSTCFLAGS=) \
+		$(if $(REALHOSTCC),HOSTCC=$(REALHOSTCC) KBUILD_HOSTCFLAGS=) \
 		$(if $(REALHOSTLD),HOSTLD=$(REALHOSTLD) KBUILD_HOSTLDFLAGS=) \
 		$(OUTPUT)fixdep
 
END
fi

if dpkg --compare-versions "$KVER" lt "6.8"; then
	cat << END | env --chdir=linux patch -p1
--- a/debian/bin/gencontrol.py
+++ b/debian/bin/gencontrol.py
@@ -74,13 +74,9 @@ class Gencontrol(Base):
         for env, attr, desc in self.env_flags:
             setattr(self, attr, False)
             if os.getenv(env):
-                if self.changelog[0].distribution == 'UNRELEASED':
-                    import warnings
-                    warnings.warn(f'Disable {desc} on request ({env} set)')
-                    setattr(self, attr, True)
-                else:
-                    raise RuntimeError(
-                        f'Unable to disable {desc} in release build ({env} set)')
+                import warnings
+                warnings.warn(f'Disable {desc} on request ({env} set)')
+                setattr(self, attr, True)
 
     def _setup_makeflags(self, names, makeflags, data):
         for src, dst, optional in names:
END
fi

if test "$KVER" = 6.8; then
	cat << 'END' | env --chdir=linux patch -p1
--- a/debian/rules
+++ b/debian/rules
@@ -93,7 +93,7 @@ endif
 
 CLEAN_PATTERNS := $(BUILD_DIR) $(STAMPS_DIR) debian/lib/python/debian_linux/*.pyc debian/lib/python/debian_linux/__pycache__ $$(find debian -maxdepth 1 -type d -name 'linux-*') debian/*-modules-*-di* debian/kernel-image-*-di* debian/*-tmp debian/*.substvars
 
-maintainerclean:
+clean-generated:
 	rm -rf $(CLEAN_PATTERNS)
 # We cannot use dh_clean here because it requires debian/control to exist
 	rm -rf debian/.debhelper debian/*.debhelper* debian/files debian/generated.*
@@ -114,6 +114,8 @@ maintainerclean:
 		debian/linux-source.maintscript \
 		debian/rules.gen \
 		debian/tests/control
+
+maintainerclean: debianclean
 	rm -rf $(filter-out debian .git, $(wildcard * .[^.]*))
 
 clean: debian/control
@@ -154,4 +156,4 @@ debian/control-real: debian/bin/gencontrol.py $(CONTROL_FILES)
 	@echo
 	exit 1
 
-.PHONY: binary binary-% build build-% clean debian/control-real orig setup source
+.PHONY: binary binary-% build build-% clean debian/control-real orig setup source clean-generated
END
fi

if true; then
	# make revision suffix more liberal to be able to recognize our
	# bookworm-backports kernel as such
	#
	# https://salsa.debian.org/kernel-team/linux/-/merge_requests/1150
	# sed -i 's/^(?:\\+b\\d+)?$/(?:\\+[a-zA-Z0-9]+)?/' debian/lib/python/debian_linux/debian.py
	cat << END | env --chdir=linux patch -p1
--- a/debian/lib/python/debian_linux/debian.py
+++ b/debian/lib/python/debian_linux/debian.py
@@ -202,7 +202,7 @@ $
         .+?
     )
 )
-(?:\+b\d+)?
+(?:\+reform[0-9]+T[0-9]+Z[0-9]*)?
 $
     """, re.X)
 
END
fi

if [ "$KVER" = "6.10" ]; then
	# patch oversight for extra control files when BinaryPackage
	# was changed from dict to dataclass
	#
	# https://salsa.debian.org/kernel-team/linux/-/merge_requests/1152
	cat << END | env --chdir=linux patch -p1
--- a/debian/lib/python/debian_linux/gencontrol.py
+++ b/debian/lib/python/debian_linux/gencontrol.py
@@ -454,7 +454,7 @@ class Gencontrol(object):

         extra_arches: dict[str, Any] = {}
         for package in packages_extra:
-            arches = package['Architecture']
+            arches = package.architecture
             for arch in arches:
                 i = extra_arches.get(arch, [])
                 i.append(package)
END
fi

if dpkg --compare-versions "$KVER" ge "6.8"; then
	# These meta-meta-packages must be provided by the MNT repositories
	# until the last installation manually removed the linux-*-arm64
	# packages in favour of linux-*-mnt-reform-arm64. If they disappear
	# from the MNT repos before that, then even installations which had the
	# linux-*-mnt-reform-arm64 packages pulled in will upgrade their
	# linux-*-arm64 to the version from Debian which will in turn pull
	# in the wrong kernel. This will only not be a disaster at the point
	# where *all* required patches were upstreamed (haha).
	if dpkg --compare-versions "$KVER" ge "6.10"; then
		# Since 1f3a3d27318a99feef7ffcdb4e302d164250af64
		# extra.control.in is broken, so we use headers.meta.control.in
		# instead. We cannot use sourcebin.meta.control.in because even
		# though the entries in debian/control will be created as
		# expected, no binary packages will get emitted. We cannot use
		# docs.meta.control.in because we are building with docs =
		# false.
		# https://salsa.debian.org/kernel-team/linux/-/merge_requests/1152#note_513085
		sed -i 's/assert len(packages_meta) == 2/assert len(packages_meta) == 4/' linux/debian/bin/gencontrol.py
		control="linux/debian/templates/headers.meta.control.in"
	else
		control="linux/debian/templates/extra.control.in"
	fi
	cat <<'END' >>"$control"

Package: linux-image-arm64
Architecture: arm64
Meta-Rules-Target: meta
Build-Profiles: <!pkg.linux.nokernel !pkg.linux.nometa>
Depends: linux-image-mnt-reform-arm64 (= ${binary:Version}), ${misc:Depends}
Section: oldlibs
Description: Linux for 64-bit ARMv8 machines (MNT Reform) (meta-meta-package)
 This meta-meta-package depends on the linux-image-mnt-reform-arm64
 meta-package for use on MNT Reform 2, MNT Pocket Reform and Reform Next to
 ensure a smooth transition after changing the kernel flavour name in 6.8.9.
 .
 This is an empty transitional package and can be safely removed as its
 functionality is provided by the linux-image-mnt-reform-arm64 package instead.

Package: linux-headers-arm64
Architecture: arm64
Meta-Rules-Target: meta
Build-Profiles: <!pkg.linux.nokernel !pkg.linux.nometa !pkg.linux.quick>
Depends: linux-headers-mnt-reform-arm64 (= ${binary:Version}), ${misc:Depends}
Section: oldlibs
Description: Linux for 64-bit ARMv8 machines (MNT Reform) (meta-meta-package)
 This meta-meta-package depends on the linux-headers-mnt-reform-arm64
 meta-package for use on MNT Reform 2, MNT Pocket Reform and Reform Next to
 ensure a smooth transition after changing the kernel flavour name in 6.8.9.
 .
 This is an empty transitional package and can be safely removed as its
 functionality is provided by the linux-headers-mnt-reform-arm64 package
 instead.
END
fi

# new toml config format since 6.7
if dpkg --compare-versions "$KVER" ge "6.7"; then
	flavour="arm64"
	# in 6.8 we changed the flavourname from "arm64" to "mnt-reform-arm64"
	if dpkg --compare-versions "$KVER" ge "6.8"; then
		flavour="mnt-reform-arm64"
	fi
	mkdir -p linux/debian/config.local/arm64
	cat << END >> linux/debian/config.local/arm64/defines.toml
[[flavour]]
name = '$flavour'
[flavour.defs]
is_default = true
[flavour.packages]
installer = false
docs = false
[flavour.description]
hardware = '64-bit ARMv8 machines (MNT Reform)'
hardware_long = 'MNT Reform 2, MNT Pocket Reform and Reform Next'

[[featureset]]
name = 'none'

[[featureset.flavour]]
name = '$flavour'

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

if dpkg --compare-versions "$KVER" lt "6.8"; then
	export DEBIAN_KERNEL_DISABLE_DEBUG=1
	export DEBIAN_KERNEL_DISABLE_INSTALLER=1
	export DEBIAN_KERNEL_DISABLE_SIGNED=1
fi

if $USE_GIT; then
	# the orig directory will contain orig.tar.gz tarballs downloaded by
	# debian/bin/genorig.py
	if [ ! -e orig ]; then
		env --chdir=linux debian/bin/genorig.py https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
	fi

	make -C linux -f debian/rules orig
fi

if dpkg --compare-versions "$KVER" ge "6.8"; then
	# renaming things like abi or flavour means that now there are files without
	# purpose in ./debian -- clean them up
	make -C linux -f debian/rules clean-generated
fi

# this command fails intentionally, so we let it always succeed
# we don't care that ":" runs even when control-real succeeds
# shellcheck disable=SC2015
make -C linux -f debian/rules debian/control-real && exit 1 || :

if dpkg --compare-versions "$KVER" lt "6.8"; then
	# running the last command creates pyc files that we don't want
	rm -r ./linux/debian/lib/python/debian_linux/__pycache__
fi

if [ ! -e "patches${KVER}" ]; then
	echo "no patches for linux $KVER prepared yet" >&2
	exit 1
fi

mkdir linux/debian/patches/reform
cp -a "patches${KVER}"/* linux/debian/patches/reform

find "patches${KVER}/" -type f -name "*.patch" | env LC_ALL=C sort | sed 's/^patches'"$KVER"'\//reform\//' >> linux/debian/patches/series

env --chdir=linux QUILT_PATCHES=debian/patches quilt push -a --fuzz=0


# The next few dozen lines create a new quilt patch containing all the device
# tree files that we copy into the kernel tree
env --chdir=linux QUILT_PATCHES=debian/patches quilt new reform/dts.patch
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/fsl-ls1028a-mnt-reform2.dts
cp fsl-ls1028a-mnt-reform2.dts linux/arch/arm64/boot/dts/freescale/fsl-ls1028a-mnt-reform2.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2-hdmi.dts
cp imx8mq-mnt-reform2-hdmi.dts linux/arch/arm64/boot/dts/freescale/imx8mq-mnt-reform2-hdmi.dts
env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/Makefile
sed -i '/fsl-ls1028a-rdb.dtb/a dtb-$(CONFIG_ARCH_LAYERSCAPE) += fsl-ls1028a-mnt-reform2.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
sed -i '/imx8mq-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_MXC) += imx8mq-mnt-reform2-hdmi.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
# pocket reform and a311d only work with 6.5 or later
if dpkg --compare-versions "$KVER" ge "6.5"; then
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mp-mnt-pocket-reform.dts
	cp imx8mp-mnt-pocket-reform.dts linux/arch/arm64/boot/dts/freescale/imx8mp-mnt-pocket-reform.dts
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/freescale/imx8mp-mnt-reform2.dts
	cp imx8mp-mnt-reform2.dts linux/arch/arm64/boot/dts/freescale/imx8mp-mnt-reform2.dts
	sed -i '/imx8mq-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_MXC) += imx8mp-mnt-pocket-reform.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
	sed -i '/imx8mq-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_MXC) += imx8mp-mnt-reform2.dtb' linux/arch/arm64/boot/dts/freescale/Makefile
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/amlogic/meson-g12b-bananapi-cm4-mnt-pocket-reform.dts
	cp meson-g12b-bananapi-cm4-mnt-pocket-reform.dts linux/arch/arm64/boot/dts/amlogic/meson-g12b-bananapi-cm4-mnt-pocket-reform.dts
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/amlogic/Makefile
	sed -i '/meson-g12b-bananapi-cm4-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_MESON) += meson-g12b-bananapi-cm4-mnt-pocket-reform.dtb' linux/arch/arm64/boot/dts/amlogic/Makefile
fi
# rk3588 needs 6.8 or later
if dpkg --compare-versions "$KVER" ge "6.8"; then
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/rockchip/rk3588-mnt-reform2.dts
	cp rk3588-mnt-reform2.dts linux/arch/arm64/boot/dts/rockchip/rk3588-mnt-reform2.dts
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/rockchip/rk3588-mnt-reform2-dsi.dts
	cp rk3588-mnt-reform2-dsi.dts linux/arch/arm64/boot/dts/rockchip/rk3588-mnt-reform2-dsi.dts
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/rockchip/rk3588-mnt-pocket-reform.dts
	cp rk3588-mnt-pocket-reform.dts linux/arch/arm64/boot/dts/rockchip/rk3588-mnt-pocket-reform.dts
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/rockchip/rk3588-mnt-reform-next.dts
	cp rk3588-mnt-reform-next.dts linux/arch/arm64/boot/dts/rockchip/rk3588-mnt-reform-next.dts
	env --chdir=linux QUILT_PATCHES=debian/patches quilt add arch/arm64/boot/dts/rockchip/Makefile
	sed -i '/rk3588-rock-5b.dtb/a dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-mnt-reform2.dtb' linux/arch/arm64/boot/dts/rockchip/Makefile
	sed -i '/rk3588-mnt-reform2.dtb/a dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-mnt-reform2-dsi.dtb' linux/arch/arm64/boot/dts/rockchip/Makefile
	sed -i '/rk3588-mnt-reform2-dsi.dtb/a dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-mnt-reform-next.dtb' linux/arch/arm64/boot/dts/rockchip/Makefile
	sed -i '/rk3588-mnt-reform-next.dtb/a dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-mnt-pocket-reform.dtb' linux/arch/arm64/boot/dts/rockchip/Makefile
fi
# finalize dts.patch
env --chdir=linux QUILT_PATCHES=debian/patches quilt refresh

# add config *after* adding patches or otherwise kconfigeditor2 will throw
# (nonfatal) warnings about config options that don't exist (yet)
if [ ! -d kernel-team ]; then
	git clone https://salsa.debian.org/kernel-team/kernel-team.git
fi

cat config >> linux/debian/config/arm64/config
# we don't care that ":" runs even when control-real succeeds
# shellcheck disable=SC2015
env --chdir=linux make -f debian/rules debian/control-real && exit 1 || :
env --chdir=linux debian/rules source
env --chdir=linux ../kernel-team/utils/kconfigeditor2/process.py .


DEB_BUILD_PROFILES="nodoc pkg.linux.nokerneldbg pkg.linux.nokerneldbginfo"
if [ "$BUILD_ARCH" != "$HOST_ARCH" ]; then
	DEB_BUILD_PROFILES="cross $DEB_BUILD_PROFILES"
fi

if [ "$HOST_ARCH" != "arm64" ]; then
	DEB_BUILD_PROFILES="pkg.linux.nokernel pkg.linux.nometa $DEB_BUILD_PROFILES"
fi

env --chdir=linux DEB_BUILD_PROFILES="$DEB_BUILD_PROFILES" \
	sbuild --chroot="$BASESUITE-$BUILD_ARCH" --arch-any --build="$BUILD_ARCH" --host="$HOST_ARCH" \
		"$([ "$HOST_ARCH" = "arm64" ] && echo --arch-all || echo --no-arch-all)" \
		--verbose --no-source-only-changes --no-run-lintian --no-run-autopkgtest

mv "./linux_$(dpkg-parsechangelog --show-field Version --file linux/debian/changelog)_$HOST_ARCH.changes" "./linux.changes"
dcmd mv "./linux.changes" "$ROOTDIR/changes"
