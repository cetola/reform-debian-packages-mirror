#!/bin/sh

set -eu

. ./common.sh

for c in changes/*.changes; do
	echo "including $c..." >&2
	reprepro include "$OURSUITE" "$c"
done

for p in $(reprepro --list-format '${source}\n' -T deb list "$OURSUITE" | sed 's/^\([^ (]\+\).*/\1/' | sort -u); do
	case p in
		linux|box64|livi|reform-tools|reform-handbook) continue;;
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
