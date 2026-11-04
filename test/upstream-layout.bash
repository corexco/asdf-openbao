#!/usr/bin/env bash

# Canary for upstream drift.
#
# Verifies that the newest OpenBao release still follows the artifact layout
# this plugin derives from it (file naming, checksums file, platforms). It is
# meant to run on a schedule (see .github/workflows/canary.yml) so that an
# upstream change shows up as a red build here instead of a broken
# `asdf install openbao latest` for users.
#
#   ./test/upstream-layout.bash

# The plugin resolves platform/arch from the environment, so this script scopes
# ASDF_OPENBAO_OVERWRITE_* overrides to subshells on purpose.
# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(dirname "$SCRIPT_DIR")

# shellcheck source=../lib/utils.bash
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/utils.bash"

# Platforms we expect upstream to keep publishing. A missing core artifact
# means the naming scheme changed (or a primary platform was dropped) and the
# plugin needs a human look.
CORE_PLATFORMS="linux/amd64 linux/arm64 darwin/amd64 darwin/arm64"
OPTIONAL_PLATFORMS="linux/armv6 linux/ppc64le linux/riscv64 linux/s390x
freebsd/amd64 freebsd/arm64 freebsd/armv6
netbsd/amd64 netbsd/arm64 netbsd/armv6
openbsd/amd64 openbsd/arm64 openbsd/armv6
windows/amd64 windows/arm64"

failures=0

asset_url() {
	local platform="$1" arch="$2"
	(
		export ASDF_OPENBAO_OVERWRITE_PLATFORM="$platform"
		export ASDF_OPENBAO_OVERWRITE_ARCH="$arch"
		release_url "$VERSION" "$(asset_name "$VERSION")"
	)
}

note_failure() {
	printf 'FAIL %s\n' "$*"
	failures=$((failures + 1))
}

VERSION="${1:-$(cd "$PLUGIN_DIR" && ./bin/latest-stable)}" || {
	echo "could not resolve the latest OpenBao version" >&2
	exit 1
}

echo "checking OpenBao $VERSION"
echo

checksum_cache="$(mktemp -d "${TMPDIR:-/tmp}/asdf-openbao-canary.XXXXXX")"
trap 'rm -rf "$checksum_cache"' EXIT

resolve_checksum_file() {
	(
		export ASDF_OPENBAO_OVERWRITE_PLATFORM="$1"
		checksum_asset_name "$VERSION"
	)
}

checksums_for() {
	local platform="$1" file
	file="$(resolve_checksum_file "$platform")"
	if [ -z "$file" ]; then
		return 1
	fi
	if [ ! -f "$checksum_cache/$file" ]; then
		if ! (
			export ASDF_OPENBAO_OVERWRITE_PLATFORM="$platform"
			fetch_checksums "$VERSION"
		) >"$checksum_cache/$file" 2>/dev/null; then
			return 1
		fi
	fi
	cat "$checksum_cache/$file"
}

check_platform() {
	local kind="$1" target="$2"
	local platform="${target%/*}" arch="${target#*/}"
	local url asset checksums

	if ! url="$(asset_url "$platform" "$arch" 2>/dev/null)"; then
		note_failure "$target: the plugin cannot derive an artifact name"
		return
	fi
	asset="${url##*/}"

	if ! curl -fsSL -I -o /dev/null "$url" 2>/dev/null; then
		if [ "$kind" = "core" ]; then
			note_failure "$target: $asset not found at $url"
		else
			printf 'note %s/%s is no longer published (%s)\n' "$platform" "$arch" "$asset"
		fi
		return
	fi

	if ! checksums="$(checksums_for "$platform")"; then
		note_failure "$target: no checksum file published for OpenBao $VERSION"
		return
	fi
	if ! printf '%s\n' "$checksums" | awk -v f="$asset" '$2 == f { found = 1 } END { exit !found }'; then
		note_failure "$target: $asset is not listed in the release checksum file"
		return
	fi

	printf 'ok   %s/%s %s\n' "$platform" "$arch" "$asset"
}

for target in $CORE_PLATFORMS; do
	check_platform core "$target"
done
for target in $OPTIONAL_PLATFORMS; do
	check_platform optional "$target"
done

echo
if [ "$failures" -eq 0 ]; then
	printf 'OpenBao %s matches the expected artifact layout\n' "$VERSION"
	exit 0
fi
printf '%s layout check(s) failed for OpenBao %s — see lib/utils.bash\n' "$failures" "$VERSION"
exit 1
