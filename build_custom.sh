#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

. ./common.sh

# this is arch:arm64 because of #1134628
cat << END | equivs-build --full --source -
Suite: reform
Maintainer: robot <reform@reform.repo>
Package: fonts-reform-iosevka-term
Version: 2.3.0.1
Architecture: arm64
Description: Versatile typeface for code, from code (transitional metapackage)
Depends: fonts-iosevka
END
