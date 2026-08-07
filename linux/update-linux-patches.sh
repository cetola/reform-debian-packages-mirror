#!/bin/bash

KERNVER=7.1

cd linux

# MNT Pocket Reform Panel Driver
PATCHFILE="../patches${KERNVER}/imx8mp-mnt-pocket-reform/pocket-panel/0001-v5-add-multi-display-panel-driver.patch"
# keep the patch header and changes to makefile and kconfig, truncate the rest
sed -z -i -E 's/diff --git a\/drivers\/gpu\/drm\/panel\/panel-mnt-pocket-reform\.c.*//' "${PATCHFILE}"
# update the main part of the patch
git diff /dev/null drivers/gpu/drm/panel/panel-mnt-pocket-reform.c >> "${PATCHFILE}"

# MNT System Controller driver (mntsc)
PATCHFILE="../patches${KERNVER}/sc/1000-mnt-sc-driver.patch"
# keep the patch header and changes to makefile and kconfig, truncate the rest
sed -z -i -E 's/diff --git a\/drivers\/firmware\/mnt-sc\.c.*//' "${PATCHFILE}"
# update the main part of the patch
git diff /dev/null drivers/firmware/mnt-sc.c >> "${PATCHFILE}"

# Analogix DP driver hacks for RK3588 eDP Hot Plug
PATCHFILE="../patches${KERNVER}/rk3588-mnt-reform2/7000-mnt-analogix-dp-changes-for-usb-c-alt-mode.patch"
# keep the patch header, truncate the rest
sed -z -i -E 's/diff --git a\/drivers\/gpu\/drm\/bridge\/analogix\/analogix_dp.*//' "${PATCHFILE}"
# update the main parts of the patch
for FILE in analogix_dp_core.c analogix_dp_core.h analogix_dp_reg.c
do
    ORIGURL="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/gpu/drm/bridge/analogix/${FILE}?h=v${KERNVER}"
    wget -O "/tmp/${FILE}" "${ORIGURL}"
    git diff "/tmp/${FILE}" "drivers/gpu/drm/bridge/analogix/${FILE}" >> "${PATCHFILE}"
done
sed -i -E 's/a\/tmp\/analogix_dp/a\/drivers\/gpu\/drm\/bridge\/analogix\/analogix_dp/' "${PATCHFILE}"

cd ..
git diff "patches${KERNVER}"
