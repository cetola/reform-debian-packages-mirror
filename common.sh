#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Copyright 2021 Helmut Grohne & Johannes Schauer Marin Rodrigues

set -e
set -u

: "${BASESUITE:=unstable}"
: "${OURSUITE:=reform}"
: "${OURLABEL:=reform}"
: "${VERSUFFIX:=reform}"
WORKDIR=$(mktemp --directory --tmpdir="$(pwd)")
PATCHDIR=$(realpath patches)
REPREPRO_BASE_DIR=$(realpath repo)
HTTP_PORT=7251
: "${MIRROR:=http://deb.debian.org/debian}"
# If we are in a git repository and if SOURCE_DATE_EPOCH is not set or set but
# null, use the timestamp of the latest git commit. Otherwise, use the provided
# value (if not null) or default to the timestamp of now.
if [ -z ${SOURCE_DATE_EPOCH:+x} ] && git -C . rev-parse 2>/dev/null; then
	SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
else
	: "${SOURCE_DATE_EPOCH:=$(date +%s)}"
fi
export SOURCE_DATE_EPOCH
export REPREPRO_BASE_DIR
HTTPD_PID=

export DEBEMAIL='robot <reform@reform.repo>'

cleanup() {
	if test -n "$HTTPD_PID"; then
		kill "$HTTPD_PID" || :
	fi
	if test -d "$WORKDIR"; then
		rm -Rf "$WORKDIR"
	fi
}

trap cleanup EXIT HUP INT TERM

python3 -m http.server --bind 127.0.0.1 --directory "$REPREPRO_BASE_DIR" "$HTTP_PORT" &
HTTPD_PID=$!

SRC_LIST_PATCHED="deb [ trusted=yes ] http://127.0.0.1:$HTTP_PORT/ $OURSUITE main"

BUILD_ARCH=$(dpkg --print-architecture)
HOST_ARCH=arm64

export DEB_BUILD_OPTIONS="noautodbgsym nocheck noudeb parallel=16"

chdistdata=$(pwd)/chdist
chdist_base() {
	local cmd
	cmd=$1
	shift
	chdist "--data-dir=$chdistdata" "$cmd" base "$@"
}

COMMON_SBUILD_OPTS="--verbose --no-clean-source --no-source-only-changes --no-run-lintian --no-run-autopkgtest --no-apt-upgrade --no-apt-distupgrade"
COMMON_BUILD_PROFILES="nodoc,nobiarch,nocheck,noudeb"

ROOTDIR="$(pwd)"
