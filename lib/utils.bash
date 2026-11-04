#!/usr/bin/env bash

# Shared helpers for the asdf-openbao plugin.
#
# This file is sourced by the bin/ scripts. Keep it compatible with bash 3.2
# (the default on macOS) and avoid non-portable commands.

set -euo pipefail

GH_REPO="https://github.com/openbao/openbao"
TOOL_NAME="openbao"
BINARY_NAME="bao"
# Command used to smoke-test an installation (`asdf plugin test` convention).
# shellcheck disable=SC2034
TOOL_TEST="bao --version"

# First released OpenBao version. Tags below this belong to the pre-fork
# HashiCorp Vault history and have no OpenBao release artifacts.
MIN_VERSION="2.0.0"

# Releases from this version on publish a single checksums.txt instead of one
# checksums-<os>.txt file per operating system.
MODERN_CHECKSUMS_VERSION="2.6.0"

# Releases from this version on use the current artifact naming scheme:
#   openbao_<version>_<os>_<arch>.tar.gz
# Older releases use:
#   bao_<version>_<Os>_<arch>.tar.gz
# where <arch> is "x86_64" instead of "amd64".
MODERN_NAMING_VERSION="2.6.0"

fail() {
	echo "asdf-$TOOL_NAME: $*" >&2
	exit 1
}

msg() {
	echo "asdf-$TOOL_NAME: $*" >&2
}

curl_opts=(-fsSL)

is_truthy() {
	case "$1" in
	1 | true | TRUE | yes | YES | on | ON) return 0 ;;
	*) return 1 ;;
	esac
}

normalize_version() {
	printf '%s' "${1#v}"
}

# Portable version sort (no `sort -V`, which is not available everywhere).
sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

# Returns 0 when the major.minor.patch part of $1 is >= that of $2.
version_ge() {
	local v1 v2 i x y
	v1="${1%%[-+]*}"
	v2="${2%%[-+]*}"

	local IFS=.
	# shellcheck disable=SC2206
	local -a a=($v1)
	# shellcheck disable=SC2206
	local -a b=($v2)

	i=0
	while [ "$i" -lt 3 ]; do
		x="${a[$i]:-0}"
		y="${b[$i]:-0}"
		case "$x" in '' | *[!0-9]*) x=0 ;; esac
		case "$y" in '' | *[!0-9]*) y=0 ;; esac
		if [ "$x" -gt "$y" ]; then
			return 0
		fi
		if [ "$x" -lt "$y" ]; then
			return 1
		fi
		i=$((i + 1))
	done

	return 0
}

# ---------------------------------------------------------------------------
# Platform / architecture detection
# ---------------------------------------------------------------------------

get_platform() {
	local platform="${ASDF_OPENBAO_OVERWRITE_PLATFORM:-$(uname -s)}"

	case "$platform" in
	Linux | linux) printf '%s' "linux" ;;
	Darwin | darwin) printf '%s' "darwin" ;;
	FreeBSD | freebsd) printf '%s' "freebsd" ;;
	NetBSD | netbsd) printf '%s' "netbsd" ;;
	OpenBSD | openbsd) printf '%s' "openbsd" ;;
	SunOS | Solaris | solaris) printf '%s' "solaris" ;;
	Illumos | illumos) printf '%s' "illumos" ;;
	MINGW* | MSYS* | CYGWIN* | mingw* | msys* | cygwin* | windows) printf '%s' "windows" ;;
	*) fail "platform '$platform' is not supported by $TOOL_NAME" ;;
	esac
}

get_arch() {
	local arch="${ASDF_OPENBAO_OVERWRITE_ARCH:-$(uname -m)}"

	case "$arch" in
	x86_64 | amd64 | X86_64) printf '%s' "amd64" ;;
	aarch64 | arm64 | ARM64) printf '%s' "arm64" ;;
	armv6l | armv6 | armv7l | armv7 | arm) printf '%s' "armv6" ;;
	ppc64le | PPC64LE) printf '%s' "ppc64le" ;;
	riscv64 | RISCV64) printf '%s' "riscv64" ;;
	s390x | S390X) printf '%s' "s390x" ;;
	*) fail "architecture '$arch' is not supported by $TOOL_NAME" ;;
	esac
}

is_hsm() {
	is_truthy "${ASDF_OPENBAO_HSM:-0}"
}

default_ext() {
	if [ "$1" = "windows" ]; then
		printf '%s' "zip"
	else
		printf '%s' "tar.gz"
	fi
}

alternative_ext() {
	if [ "$1" = "windows" ]; then
		printf '%s' "tar.gz"
	else
		printf '%s' "zip"
	fi
}

legacy_platform() {
	case "$1" in
	linux) printf '%s' "Linux" ;;
	darwin) printf '%s' "Darwin" ;;
	freebsd) printf '%s' "Freebsd" ;;
	netbsd) printf '%s' "Netbsd" ;;
	openbsd) printf '%s' "Openbsd" ;;
	solaris) printf '%s' "Solaris" ;;
	illumos) printf '%s' "Illumos" ;;
	windows) printf '%s' "Windows" ;;
	*) fail "platform '$1' is not supported by $TOOL_NAME releases using the legacy artifact naming scheme" ;;
	esac
}

legacy_arch() {
	if [ "$1" = "amd64" ]; then
		printf '%s' "x86_64"
	else
		printf '%s' "$1"
	fi
}

# The naming scheme a version is expected to use.
primary_scheme() {
	if version_ge "$(normalize_version "$1")" "$MODERN_NAMING_VERSION"; then
		printf '%s' "modern"
	else
		printf '%s' "legacy"
	fi
}

alternative_scheme() {
	if [ "$(primary_scheme "$1")" = "modern" ]; then
		printf '%s' "legacy"
	else
		printf '%s' "modern"
	fi
}

# asset_name <version> [modern|legacy] [tar.gz|zip]
#
# Prints the release artifact name for the current platform. When the scheme
# or extension is omitted, the ones expected for <version> are used.
asset_name() {
	local version platform arch scheme ext prefix
	version="$(normalize_version "$1")"
	scheme="${2:-$(primary_scheme "$version")}"
	platform="$(get_platform)"
	arch="$(get_arch)"
	ext="${3:-$(default_ext "$platform")}"

	if [ "$scheme" = "modern" ]; then
		prefix="openbao"
		if is_hsm; then
			prefix="openbao-hsm"
			case "$platform:$arch" in
			linux:amd64 | linux:arm64) ;;
			*) fail "HSM builds are only published for linux/amd64 and linux/arm64" ;;
			esac
		fi
	else
		prefix="bao"
		arch="$(legacy_arch "$arch")"
		if is_hsm; then
			prefix="bao-hsm"
			case "$platform:$arch" in
			linux:x86_64 | linux:arm64) ;;
			*) fail "HSM builds are only published for Linux/x86_64 and Linux/arm64" ;;
			esac
		fi
		platform="$(legacy_platform "$platform")"
	fi

	printf '%s_%s_%s_%s.%s' "$prefix" "$version" "$platform" "$arch" "$ext"
}

release_url() {
	printf '%s/releases/download/v%s/%s' "$GH_REPO" "$(normalize_version "$1")" "$2"
}

checksum_asset_name() {
	local version scheme
	version="$(normalize_version "$1")"
	scheme="${2:-}"

	if [ -z "$scheme" ]; then
		if version_ge "$version" "$MODERN_CHECKSUMS_VERSION"; then
			scheme="modern"
		else
			scheme="legacy"
		fi
	fi

	if [ "$scheme" = "modern" ]; then
		printf '%s' "checksums.txt"
	elif is_hsm; then
		printf '%s' "checksums-linux-hsm.txt"
	else
		printf '%s' "checksums-$(get_platform).txt"
	fi
}

# ---------------------------------------------------------------------------
# Version listing
# ---------------------------------------------------------------------------

# Stable versions are plain <major>.<minor>.<patch>; anything with a suffix
# (alpha/beta/development snapshots) is a pre-release.
is_stable_version() {
	case "$1" in
	'' | *[!0-9.]* | .* | *. | *..*) return 1 ;;
	esac
	local IFS=.
	local -a parts
	# shellcheck disable=SC2206
	parts=($1)
	[ "${#parts[@]}" -eq 3 ]
}

include_prereleases() {
	is_truthy "${ASDF_OPENBAO_INCLUDE_PRERELEASES:-0}"
}

# Version tags are read from git so that listing versions needs no API token
# and stays cheap (the GitHub releases API payload is tens of megabytes).
# A tag occasionally exists without a release (e.g. 2.4.2), which is why
# bin/latest-stable probes the download URL of each candidate.
list_tag_versions() {
	git ls-remote --tags --refs "$GH_REPO" 2>/dev/null |
		sed 's|.*refs/tags/||; s/^v//' |
		awk -v min="$MIN_VERSION" '
			BEGIN { split(min, m, ".") }
			{
				base = $0
				sub(/[-+].*$/, "", base)
				if (split(base, a, ".") != 3) next
				if (a[1] !~ /^[0-9]+$/ || a[2] !~ /^[0-9]+$/ || a[3] !~ /^[0-9]+$/) next
				if (a[1] + 0 < m[1] + 0) next
				if (a[1] + 0 == m[1] + 0 && a[2] + 0 < m[2] + 0) next
				if (a[1] + 0 == m[1] + 0 && a[2] + 0 == m[2] + 0 && a[3] + 0 < m[3] + 0) next
				if (seen[$0]++) next
				print
			}'
}

list_all_versions() {
	local version
	list_tag_versions |
		while read -r version; do
			[ -n "$version" ] || continue
			if include_prereleases || is_stable_version "$version"; then
				printf '%s\n' "$version"
			fi
		done
}

# ---------------------------------------------------------------------------
# Download / install helpers
# ---------------------------------------------------------------------------

sha256_of() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$file" | awk '{print $NF}'
	else
		fail "no sha256 tool (sha256sum, shasum or openssl) is available"
	fi
}

# Prints the release checksum file for <version>. Tries the layout expected
# for that version first, then the other one (the layout changed in 2.6.0).
fetch_checksums() {
	local version="$1" schemes scheme url checksums

	if version_ge "$version" "$MODERN_CHECKSUMS_VERSION"; then
		schemes="modern legacy"
	else
		schemes="legacy modern"
	fi

	for scheme in $schemes; do
		url="$(release_url "$version" "$(checksum_asset_name "$version" "$scheme")")"
		if checksums="$(curl "${curl_opts[@]}" "$url" 2>/dev/null)"; then
			printf '%s' "$checksums"
			return 0
		fi
	done

	return 1
}

verify_checksum() {
	local version="$1" asset="$2" archive="$3"
	local checksums expected actual

	if is_truthy "${ASDF_OPENBAO_SKIP_CHECKSUM:-0}"; then
		msg "WARNING: skipping checksum verification (ASDF_OPENBAO_SKIP_CHECKSUM is set)"
		return 0
	fi

	if ! checksums="$(fetch_checksums "$version")"; then
		msg "WARNING: no checksum file published for $TOOL_NAME $version, skipping verification"
		return 0
	fi

	expected="$(printf '%s\n' "$checksums" | awk -v f="$asset" '$2 == f { print $1; exit }')"
	[ -n "$expected" ] || fail "no checksum listed for $asset"

	actual="$(sha256_of "$archive")"
	if [ "$expected" != "$actual" ]; then
		fail "checksum mismatch for $asset (expected $expected, got $actual)"
	fi
}

extract_archive() {
	local archive="$1" dest="$2"
	case "$archive" in
	*.zip)
		command -v unzip >/dev/null 2>&1 || fail "unzip is required to extract $archive"
		unzip -q -o "$archive" -d "$dest"
		;;
	*.tar.gz)
		tar -xzf "$archive" -C "$dest"
		;;
	*)
		fail "unsupported archive format: $archive"
		;;
	esac
}

# Downloads the best matching release artifact into dest and prints
# "<asset name> <path to archive>" on success.
download_archive() {
	local version="$1" dest="$2"
	local platform scheme ext asset url file attempts=0 last_error=""

	version="$(normalize_version "$version")"
	platform="$(get_platform)"

	for scheme in "$(primary_scheme "$version")" "$(alternative_scheme "$version")"; do
		for ext in "$(default_ext "$platform")" "$(alternative_ext "$platform")"; do
			asset="$(asset_name "$version" "$scheme" "$ext")"
			url="$(release_url "$version" "$asset")"
			attempts=$((attempts + 1))
			if [ "$attempts" -eq 1 ]; then
				msg "downloading $url"
			else
				msg "trying $url"
			fi
			file="$dest/archive.$ext"
			if curl "${curl_opts[@]}" -o "$file" "$url" 2>"$dest/curl.err"; then
				printf '%s %s\n' "$asset" "$file"
				return 0
			fi
			last_error="$(cat "$dest/curl.err")"
		done
	done

	[ -z "$last_error" ] || msg "$last_error"
	return 1
}

download_release() {
	local version="$1" download_path="$2"
	local tmp_dir result asset archive source

	version="$(normalize_version "$version")"
	[ -n "$download_path" ] || fail "ASDF_DOWNLOAD_PATH is not set"

	if [ "${ASDF_INSTALL_TYPE:-version}" != "version" ]; then
		fail "only OpenBao releases can be installed, '$version' is a git ref (ref installs are not supported)"
	fi

	tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/asdf-$TOOL_NAME.XXXXXX")"

	if ! result="$(download_archive "$version" "$tmp_dir")"; then
		rm -rf "$tmp_dir"
		fail "could not download $TOOL_NAME $version for $(get_platform)/$(get_arch): no matching release artifact found"
	fi
	asset="${result%% *}"
	archive="${result#* }"

	verify_checksum "$version" "$asset" "$archive"

	mkdir -p "$tmp_dir/extract"
	if ! extract_archive "$archive" "$tmp_dir/extract"; then
		rm -rf "$tmp_dir"
		fail "could not extract $asset"
	fi

	source="$tmp_dir/extract"
	# Tolerate archives that wrap their content in a top-level directory.
	if [ "$(find "$source" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ] &&
		[ -d "$(find "$source" -mindepth 1 -maxdepth 1)" ]; then
		source="$(find "$source" -mindepth 1 -maxdepth 1)"
	fi
	if [ ! -f "$source/$BINARY_NAME" ] && [ ! -f "$source/bin/$BINARY_NAME" ]; then
		rm -rf "$tmp_dir"
		fail "archive $asset does not contain the $BINARY_NAME executable"
	fi

	rm -rf "$download_path"
	mkdir -p "$download_path"
	cp -R "$source"/. "$download_path"/
	rm -rf "$tmp_dir"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}"
	local download_path="${4:-${ASDF_DOWNLOAD_PATH:-}}"
	local created_tmp="0"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	version="$(normalize_version "$version")"

	if [ -z "$download_path" ] || [ ! -d "$download_path" ]; then
		download_path="$(mktemp -d "${TMPDIR:-/tmp}/asdf-$TOOL_NAME.XXXXXX")"
		created_tmp="1"
		download_release "$version" "$download_path"
	fi

	if ! (
		mkdir -p "$install_path/bin"
		cp -R "$download_path"/. "$install_path"/

		if [ -f "$install_path/$BINARY_NAME" ]; then
			mv "$install_path/$BINARY_NAME" "$install_path/bin/$BINARY_NAME"
		fi
		[ -f "$install_path/bin/$BINARY_NAME" ] ||
			fail "expected $install_path/bin/$BINARY_NAME to exist after unpacking"
		chmod +x "$install_path/bin/$BINARY_NAME"
	); then
		rm -rf "$install_path"
		fail "an error occurred while installing $TOOL_NAME $version"
	fi

	if [ "$created_tmp" = "1" ]; then
		rm -rf "$download_path"
	fi

	echo "$TOOL_NAME $version installation was successful!"
}
