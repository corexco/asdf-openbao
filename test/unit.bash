#!/usr/bin/env bash

# Offline unit tests for lib/utils.bash. No network access required.
#
#   ./test/unit.bash

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../lib/utils.bash
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/utils.bash"

tests=0
failures=0

assert_eq() {
	local description="$1" expected="$2" actual="$3"
	tests=$((tests + 1))
	if [ "$expected" = "$actual" ]; then
		printf 'ok   %s\n' "$description"
	else
		printf 'FAIL %s\n       expected: [%s]\n       actual:   [%s]\n' \
			"$description" "$expected" "$actual"
		failures=$((failures + 1))
	fi
}

# Runs a function expecting it to fail, without aborting the test run.
assert_fails() {
	local description="$1"
	shift
	tests=$((tests + 1))
	if ("$@" >/dev/null 2>&1); then
		printf 'FAIL %s\n       expected a non-zero exit status\n' "$description"
		failures=$((failures + 1))
	else
		printf 'ok   %s\n' "$description"
	fi
}

check_asset() {
	local description="$1" version="$2" platform="$3" arch="$4"
	local expected="$5" scheme="${6:-}" ext="${7:-}" hsm="${8:-0}"

	assert_eq "$description" "$expected" "$(
		ASDF_OPENBAO_OVERWRITE_PLATFORM="$platform" \
			ASDF_OPENBAO_OVERWRITE_ARCH="$arch" \
			ASDF_OPENBAO_HSM="$hsm" \
			asset_name "$version" "$scheme" "$ext"
	)"
}

echo "# version helpers"

assert_eq "normalize_version strips a leading v" "2.7.2" "$(normalize_version v2.7.2)"
assert_eq "normalize_version keeps plain versions" "2.7.2" "$(normalize_version 2.7.2)"

if version_ge 2.7.2 2.6.0; then r=yes; else r=no; fi
assert_eq "version_ge 2.7.2 >= 2.6.0" "yes" "$r"
if version_ge 2.6.0 2.6.0; then r=yes; else r=no; fi
assert_eq "version_ge 2.6.0 >= 2.6.0" "yes" "$r"
if version_ge 2.5.5 2.6.0; then r=yes; else r=no; fi
assert_eq "version_ge 2.5.5 >= 2.6.0" "no" "$r"
if version_ge 2.10.0 2.9.9; then r=yes; else r=no; fi
assert_eq "version_ge 2.10.0 >= 2.9.9" "yes" "$r"
if version_ge 2.0.0-beta20240618 2.0.0; then r=yes; else r=no; fi
assert_eq "version_ge ignores pre-release suffixes" "yes" "$r"

assert_eq "sort_versions orders numerically" "2.5.5 2.6.0 2.7.2 2.7.10 2.10.0" \
	"$(printf '%s\n' 2.7.10 2.6.0 2.10.0 2.7.2 2.5.5 | sort_versions | xargs)"

if is_stable_version 2.7.2; then r=yes; else r=no; fi
assert_eq "is_stable_version accepts 2.7.2" "yes" "$r"
if is_stable_version 2.0.0-beta20240618; then r=yes; else r=no; fi
assert_eq "is_stable_version rejects pre-releases" "no" "$r"
if is_stable_version 2.7; then r=yes; else r=no; fi
assert_eq "is_stable_version rejects partial versions" "no" "$r"
if is_stable_version 2.7.2.1; then r=yes; else r=no; fi
assert_eq "is_stable_version rejects four-part versions" "no" "$r"

echo "# asset names (current naming scheme, >= 2.6.0)"

check_asset "linux/amd64" 2.7.2 linux amd64 "openbao_2.7.2_linux_amd64.tar.gz"
check_asset "linux/arm64" 2.6.0 linux arm64 "openbao_2.6.0_linux_arm64.tar.gz"
check_asset "linux/armv6" 2.7.1 linux armv6 "openbao_2.7.1_linux_armv6.tar.gz"
check_asset "linux/ppc64le" 2.7.1 linux ppc64le "openbao_2.7.1_linux_ppc64le.tar.gz"
check_asset "linux/s390x" 2.7.1 linux s390x "openbao_2.7.1_linux_s390x.tar.gz"
check_asset "darwin/arm64" 2.7.2 darwin arm64 "openbao_2.7.2_darwin_arm64.tar.gz"
check_asset "freebsd/amd64" 2.7.2 freebsd amd64 "openbao_2.7.2_freebsd_amd64.tar.gz"
check_asset "openbsd/arm64" 2.7.2 openbsd arm64 "openbao_2.7.2_openbsd_arm64.tar.gz"
check_asset "windows/amd64 uses zip" 2.7.2 windows amd64 "openbao_2.7.2_windows_amd64.zip"
check_asset "version may carry a leading v" v2.7.2 linux amd64 "openbao_2.7.2_linux_amd64.tar.gz"

echo "# asset names (legacy naming scheme, < 2.6.0)"

check_asset "linux/amd64 becomes x86_64" 2.5.5 linux amd64 "bao_2.5.5_Linux_x86_64.tar.gz"
check_asset "linux/arm64" 2.0.0 linux arm64 "bao_2.0.0_Linux_arm64.tar.gz"
check_asset "darwin/arm64" 2.1.1 darwin arm64 "bao_2.1.1_Darwin_arm64.tar.gz"
check_asset "solaris/amd64 (legacy only)" 2.0.3 solaris amd64 "bao_2.0.3_Solaris_x86_64.tar.gz"
check_asset "illumos/amd64 (legacy only)" 2.2.2 illumos amd64 "bao_2.2.2_Illumos_x86_64.tar.gz"
check_asset "windows/amd64 uses zip" 2.5.5 windows amd64 "bao_2.5.5_Windows_x86_64.zip"

echo "# asset names (HSM builds)"

check_asset "HSM linux/amd64 (current)" 2.6.5 linux amd64 \
	"openbao-hsm_2.6.5_linux_amd64.tar.gz" "" "" 1
check_asset "HSM linux/amd64 (legacy)" 2.5.5 linux amd64 \
	"bao-hsm_2.5.5_Linux_x86_64.tar.gz" "" "" 1
# shellcheck disable=SC2317,SC2329 # invoked indirectly by assert_fails
hsm_on_darwin() {
	export ASDF_OPENBAO_OVERWRITE_PLATFORM=darwin
	export ASDF_OPENBAO_HSM=1
	asset_name 2.6.5
}
assert_fails "HSM on darwin is not published" hsm_on_darwin

echo "# asset names (explicit scheme/extension fallbacks)"

check_asset "alternative scheme for 2.0.0-alpha (zip)" 2.0.0-alpha20240329 linux amd64 \
	"openbao_2.0.0-alpha20240329_linux_amd64.zip" modern zip
check_asset "tar.gz fallback for a legacy version" 2.5.5 linux amd64 \
	"bao_2.5.5_Linux_x86_64.tar.gz" legacy tar.gz

echo "# checksum file names"

assert_eq "checksums.txt for >= 2.6.0" "checksums.txt" "$(checksum_asset_name 2.7.2)"
assert_eq "per-OS checksums for < 2.6.0" "checksums-linux.txt" \
	"$(ASDF_OPENBAO_OVERWRITE_PLATFORM=linux checksum_asset_name 2.5.5)"
assert_eq "HSM checksums for < 2.6.0" "checksums-linux-hsm.txt" \
	"$(ASDF_OPENBAO_HSM=1 checksum_asset_name 2.5.5)"
assert_eq "illumos checksums" "checksums-illumos.txt" \
	"$(ASDF_OPENBAO_OVERWRITE_PLATFORM=illumos checksum_asset_name 2.2.2)"

echo "# install layout"

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/asdf-openbao-test.XXXXXX")"
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/download/bin"
printf '#!/bin/sh\necho fake bao\n' >"$sandbox/download/bin/bao"
printf 'license text\n' >"$sandbox/download/LICENSE"

assert_eq "install_version succeeds" "0" "$(
	install_version version 2.7.2 "$sandbox/install" "$sandbox/download" >/dev/null 2>&1
	echo $?
)"
assert_eq "install_version places bin/bao" "LICENSE bin bin/bao" \
	"$(cd "$sandbox/install" && find . -mindepth 1 -maxdepth 2 | sed 's|^\./||' | sort | xargs)"
if [ -x "$sandbox/install/bin/bao" ]; then r=yes; else r=no; fi
assert_eq "bin/bao is executable" "yes" "$r"

mkdir -p "$sandbox/empty-download"
assert_fails "install_version fails without a bao binary" \
	install_version version 2.7.2 "$sandbox/install-empty" "$sandbox/empty-download"
assert_eq "failed install leaves no install path" "" \
	"$(ls "$sandbox/install-empty" 2>/dev/null)"

assert_fails "install_version rejects ref installs" \
	install_version ref main "$sandbox/install-ref" "$sandbox/download"

echo
if [ "$failures" -eq 0 ]; then
	printf '%s tests passed\n' "$tests"
	exit 0
fi
printf '%s of %s tests failed\n' "$failures" "$tests"
exit 1
