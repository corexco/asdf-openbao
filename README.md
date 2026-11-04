# asdf-openbao

[asdf](https://asdf-vm.com) plugin for [OpenBao](https://openbao.org) — the open
source, community-driven fork of HashiCorp Vault.

Installs the official prebuilt `bao` binaries published on the
[OpenBao releases page](https://github.com/openbao/openbao/releases) and verifies
them against the release `checksums` files.

## Install

```shell
asdf plugin add openbao https://github.com/corexco/asdf-openbao.git
```

Once the plugin is part of the
[asdf plugin index](https://github.com/asdf-vm/asdf-plugins) you can also use:

```shell
asdf plugin add openbao
```

## Use

```shell
# List available versions
asdf list all openbao

# Install a specific version (the "v" prefix is optional)
asdf install openbao 2.7.2
asdf install openbao v2.7.2

# Install the latest stable release
asdf install openbao latest

# Pin the version for a project
asdf set openbao 2.7.2

# Use it
bao --version
bao server -dev
```

## Supported platforms

OpenBao publishes binaries for:

| OS      | Architectures                                |
| :------ | :------------------------------------------- |
| Linux   | amd64, arm64, armv6, ppc64le, riscv64, s390x |
| macOS   | amd64, arm64                                 |
| FreeBSD | amd64, arm64, armv6                          |
| NetBSD  | amd64, arm64, armv6                          |
| OpenBSD | amd64, arm64, armv6                          |
| Solaris / illumos | amd64 (OpenBao < 2.6.0 only)       |
| Windows | amd64, arm64 (via Git Bash / MSYS2)          |

HSM-enabled builds (`ASDF_OPENBAO_HSM=1`) are available for Linux amd64/arm64 on
OpenBao 2.2.0 – 2.6.x.

## Options

All options are read from the environment:

| Variable | Description |
| :------- | :---------- |
| `ASDF_OPENBAO_HSM` | Set to `1` to install the HSM-enabled `bao` build (Linux amd64/arm64 only). |
| `ASDF_OPENBAO_SKIP_CHECKSUM` | Set to `1` to skip SHA256 verification of the downloaded archive. Not recommended. |
| `ASDF_OPENBAO_INCLUDE_PRERELEASES` | Set to `1` to include alpha/beta releases in `asdf list all openbao`. |
| `ASDF_OPENBAO_OVERWRITE_PLATFORM` | Override platform detection: `linux`, `darwin`, `freebsd`, `netbsd`, `openbsd`, `illumos`, `solaris`, `windows`. |
| `ASDF_OPENBAO_OVERWRITE_ARCH` | Override architecture detection: `amd64`, `arm64`, `armv6`, `ppc64le`, `riscv64`, `s390x`. |

Examples:

```shell
# HSM build
ASDF_OPENBAO_HSM=1 asdf install openbao 2.6.5

# Install a foreign-platform binary (e.g. for a container image build)
ASDF_OPENBAO_OVERWRITE_PLATFORM=linux ASDF_OPENBAO_OVERWRITE_ARCH=arm64 \
  asdf install openbao 2.7.2
```

## Notes

- **Versions come from git tags.** Listing versions uses `git ls-remote` instead
  of the GitHub releases API, which keeps `asdf list all openbao` fast and free of
  API rate limits. A tag does occasionally exist without a matching release
  (e.g. `2.4.2`); installing it fails with a clear error, and `asdf latest openbao`
  always verifies that the artifact for your platform actually exists.
- **Legacy artifact naming.** Releases before 2.6.0 are published as
  `bao_<version>_<Os>_<arch>.tar.gz` with `x86_64` instead of `amd64`. The plugin
  detects the scheme from the version, and falls back to the other scheme and
  archive extension if needed (the `2.0.0-alpha` release only ships `.zip` files).
- **Checksums.** Since 2.6.0 the releases ship a single `checksums.txt`; earlier
  releases ship `checksums-<os>.txt` (plus `checksums-linux-hsm.txt` for HSM
  builds). Downloads are verified against those files. Pre-releases without a
  checksum file produce a warning and are installed unverified.
- **Ref installs** (`asdf install openbao ref:...`) are not supported; only
  released binaries are installed.

## Keeping the plugin up to date

Most of the upkeep is automatic:

- **New OpenBao releases need no plugin change.** `bin/list-all` reads the git
  tags at run time, so a new `v2.x.y` tag is installable as soon as OpenBao
  publishes it — there is no version list to bump.
- **`.github/workflows/canary.yml` runs daily** (and on demand) and does three
  things: checks that the newest release still matches the artifact layout this
  plugin derives (`test/upstream-layout.bash`), installs `latest` on Linux and
  macOS, and re-tests the legacy artifact layout (2.5.5) and an HSM build.
- **Dependabot** bumps the GitHub Actions used by the workflows weekly.
- **Push/PR tests** (`.github/workflows/test.yml`) run the offline unit tests and
  `asdf plugin test`, and lint runs shellcheck/shfmt.

The remaining hard-coded upstream facts live at the top of `lib/utils.bash`:

| Constant / code | Update when |
| :-------------- | :---------- |
| `MIN_VERSION` | OpenBao ever publishes releases below 2.0.0 (they are pre-fork Vault history). |
| `MODERN_NAMING_VERSION` | The artifact naming scheme changes again (a third scheme). The canary fails first. |
| `MODERN_CHECKSUMS_VERSION` | The checksum file layout changes again. The canary fails first. |
| `get_platform` / `get_arch` | OpenBao adds or drops an OS/architecture (the canary reports dropped optional platforms as notes, and dropped core platforms as failures). |
| `GH_REPO` | The releases ever move away from `github.com/openbao/openbao`. |

Two upstream quirks need no action:

- A git tag with no release (e.g. `2.4.2`) is still listed by `asdf list all`,
  because version discovery is tag based. Installing it fails with a clear error,
  and `asdf latest` skips it by probing the artifact URL first.
- HSM builds disappeared in 2.7.x. `ASDF_OPENBAO_HSM=1` keeps working as-is if
  upstream resumes publishing them.

One-time, human-only tasks:

- Submit the plugin to the [asdf plugin index](https://github.com/asdf-vm/asdf-plugins)
  so `asdf plugin add openbao` works without a URL.
- Optionally tag plugin releases (`v1.0.0`, ...) so users can pin
  `--asdf-plugin-gitref`.

## Development

The plugin is plain bash (bash 3.2 compatible, so it works with the system bash
on macOS) with no dependencies beyond `curl`, `git` and `tar`.

```shell
git clone https://github.com/corex/asdf-openbao.git
cd asdf-openbao

# Lint and format (requires shellcheck and shfmt)
make lint
make format

# Offline unit tests
make test-unit

# Check the newest upstream release still matches the expected layout
./test/upstream-layout.bash

# Run the plugin against the real OpenBao releases
asdf plugin add openbao "$PWD"
asdf plugin test openbao "$PWD" --asdf-tool-version 2.7.2 'bao --version'
```

### Plugin scripts

| Script | Purpose |
| :----- | :------ |
| `bin/list-all` | List installable versions (stable by default). |
| `bin/latest-stable` | Resolve the newest installable version for this platform, with an optional prefix filter. |
| `bin/download` | Download the release archive into `$ASDF_DOWNLOAD_PATH` and verify its checksum. |
| `bin/install` | Install the unpacked release into `$ASDF_INSTALL_PATH/bin`. |
| `bin/help.*` | `asdf help openbao` output. |

## License

[MIT](LICENSE)
