#!/bin/sh
# Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.
#
# Keeps the compiled-in version (Sources/AxolotyVersion/AxolotyVersion.swift)
# derived from the root VERSION file.
#
#   stamp-version.sh check   [ROOT]  fail unless compiledVersion is "<VERSION>-dev"
#   stamp-version.sh release [ROOT]  check, then rewrite it to "<VERSION>"
#
# The committed value is the development form, so only the release workflow
# ever produces a binary that reports a bare release number, and it derives
# that number from VERSION rather than from a second hand-edited literal.
set -eu

mode=${1:-}
root=${2:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
file="$root/Sources/AxolotyVersion/AxolotyVersion.swift"
[ -f "$root/VERSION" ] && [ -f "$file" ] || { echo "stamp-version: VERSION or $file missing" >&2; exit 2; }

version=$(tr -d '[:space:]' < "$root/VERSION")
case "$version" in
    ''|*[!0-9A-Za-z.+-]*) echo "stamp-version: invalid VERSION '$version'" >&2; exit 2 ;;
esac

pattern='^    public static let compiledVersion = "\(.*\)"$'
current=$(sed -n "s/$pattern/\\1/p" "$file")
if [ "$current" != "$version-dev" ]; then
    echo "stamp-version: compiledVersion is '$current' but VERSION is '$version' (expected '$version-dev')." >&2
    echo "Update the literal in $file to \"$version-dev\" before releasing." >&2
    exit 1
fi

case "$mode" in
    check) ;;
    release)
        tmp="$file.stamp"
        sed "s/$pattern/    public static let compiledVersion = \"$version\"/" "$file" > "$tmp"
        mv "$tmp" "$file"
        [ "$(sed -n "s/$pattern/\\1/p" "$file")" = "$version" ] || { echo "stamp-version: stamping failed" >&2; exit 1; }
        ;;
    *) echo "usage: stamp-version.sh check|release [ROOT]" >&2; exit 2 ;;
esac
