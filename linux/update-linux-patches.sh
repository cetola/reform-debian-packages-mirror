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

cd ..
git diff "patches${KERNVER}"
