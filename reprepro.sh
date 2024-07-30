#!/bin/sh

set -eu

. ./common.sh

for c in changes/*.changes; do
	echo "including $c..." >&2
	reprepro include "$OURSUITE" "$c"
done

# include binary out-of-tree driver modules
for d in reform-qcacld2*.deb fonts-reform-iosevka-term_2.3.0-1_all.deb; do
	echo "including $d..." >&2
	reprepro includedeb "$OURSUITE" "$d"
done

for p in $(reprepro --list-format '${source}\n' -T deb list "$OURSUITE" | sed 's/^\([^ (]\+\).*/\1/' | sort -u); do
	case $p in
		linux|box64|reform-tools|reform-handbook|pocket-reform-handbook|wayfire|wayfire-dev|libwf-touch-dev|libwf-utils-dev|libwf-utils0|firedecor) continue;;
	esac

	if [ ! -e "patches/$p" ]; then
		echo "patches/$p doesn't exist -- removing from repo"
		reprepro removesrc "$OURSUITE" "$p"
		continue
	fi

	if [ ! -x "patches/$p" ]; then
		echo "patches/$p is not executable --removing from repo"
		reprepro removesrc "$OURSUITE" "$p"
		continue
	fi
done
