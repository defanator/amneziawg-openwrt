# amneziawg-openwrt

This repo is a fork of original [amneziawg-openwrt](https://github.com/amnezia-vpn/amneziawg-openwrt) one with a few extra things intended to help with creating reproducible builds of the AmneziaWG package artifacts for different versions and architectures supported by OpenWrt.

The idea is to keep it up to date with the upstream for all the general sources. All the extra features are basically combined into a top-level [Makefile](Makefile) and a set of GitHub action [workflows](.github/workflows/).

## OpenWrt package feed

Custom OpenWrt package feed with binary packages built using pipelines of this repository is available [here](https://etaoin.shrdlu.club/openwrt-amneziawg/).

Please note that it does include quite limited number of targets.
If your target is not available, you may want to [open an issue](https://github.com/defanator/amneziawg-openwrt/issues), or refer to alternative builds available out there such as [https://github.com/Slava-Shchipunov/awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt).

## Added features

 1. [Makefile](Makefile) providing a number of targets:
    ```
    % make

    Targets:
      help                    Show help message (list targets)
      show-env                Show environment details
      export-env              Export environment
      build-amneziawg         Build amneziawg-openwrt kernel module and packages
      prepare-artifacts       Save amneziawg-openwrt artifacts from regular builds
      check-release           Verify that everything is in place for tagged release
      create-feed-archive     Create archive of a package feed
      prepare-release         Save amneziawg-openwrt artifacts from tagged release
      create-feed             Create package feed
      verify-feed             Verify package feed
    ```
    Additional targets (`prepare`, `fix-host-symlinks`, `build-kernel`) are provided by [openwrt-crossbuild-env](https://github.com/defanator/openwrt-crossbuild-env) and become available when that repository is checked out alongside this one (see below).

    It is heavily used by GitHub actions (see below), but it also can be used directly on host platforms to prepare an environment for building OpenWrt packages, including kernel modules.

 2. GitHub action workflows, in particular:
       - [multibuild-module-artifacts](.github/workflows/multibuild-module-artifacts.yml) - builds AmneziaWG packages for multiple OpenWrt versions and target architectures using a matrix generated from [ci/target-matrix-config.yaml](ci/target-matrix-config.yaml); runs on a schedule and can be triggered manually;
       - [create-release-from-multibuild](.github/workflows/create-release-from-multibuild.yml) - builds packages for all configured targets and publishes a GitHub release when a `v*.*.*` tag is pushed.

    Both workflows use [openwrt-crossbuild-env](https://github.com/defanator/openwrt-crossbuild-env) for cross-compilation environment and target matrix generation.

## Build environment: openwrt-crossbuild-env

[openwrt-crossbuild-env](https://github.com/defanator/openwrt-crossbuild-env) provides a virtualized cross-compilation environment for OpenWrt development. It is used both by the GitHub Actions workflows in this repository and can be used for local development.

Key components:
- `Makefile.crossbuild` — included automatically by this repository's [Makefile](Makefile) (via `-include`) when `openwrt-crossbuild-env` is checked out alongside this repo. Provides the `prepare`, `fix-host-symlinks`, and `build-kernel` targets, as well as `OPENWRT_*` variable defaults.
- `generate-target-matrix` — generates the CI build matrix from [ci/target-matrix-config.yaml](ci/target-matrix-config.yaml) in this repository, producing target-specific build parameters (including `vermagic`).
- Local development via [Vagrant](https://www.vagrantup.com/) with VMware Fusion/Workstation, VirtualBox, or libvirt as the virtualization provider.

Refer to the [openwrt-crossbuild-env README](https://github.com/defanator/openwrt-crossbuild-env#readme) for local environment setup details.

## Building AmneziaWG packages

The [multibuild-module-artifacts](.github/workflows/multibuild-module-artifacts.yml) workflow builds packages for all targets defined in [ci/target-matrix-config.yaml](ci/target-matrix-config.yaml) and runs automatically on a schedule. It can also be triggered manually with a custom list of OpenWrt versions.

### With GitHub actions from UI

Go to the Actions menu, select "build module artifacts for multiple targets" workflow on the left, click on the "Run workflow" drop-down on the right. Optionally enter a space-separated list of OpenWrt versions to build (defaults to the repository variable `DEFAULT_OPENWRT_VERSIONS`), then press "Run workflow" to initiate the job.

### With GitHub actions from CLI

Use the GitHub CLI to trigger the workflow:
```
% gh workflow run multibuild-module-artifacts.yml -f openwrt_versions="25.12.0 24.10.5 23.05.3"
```

Use `--ref` to target a specific branch or tag:
```
% gh workflow run multibuild-module-artifacts.yml --ref main -f openwrt_versions="25.12.0 24.10.5 23.05.3"
```

### Locating the artifacts

Go to the workflow summary page and look for "Artifacts produced during runtime" section in the bottom. Each artifact is named using the pattern:
```
amneziawg-<version>-openwrt-<release>-<arch>-<target>-<subtarget>
```

### Manually on a host VM/instance

Set up [openwrt-crossbuild-env](https://github.com/defanator/openwrt-crossbuild-env) following its README instructions. Then, from a shared parent directory, check out the `amneziawg-openwrt` and `openwrt` repositories alongside it:
```
% mkdir -p ${HOME}/openwrt-playground && cd ${HOME}/openwrt-playground
% git clone https://github.com/defanator/openwrt-crossbuild-env.git
% git clone https://github.com/defanator/amneziawg-openwrt.git
% git clone https://github.com/openwrt/openwrt.git
% cd amneziawg-openwrt
```

Set your build details via `OPENWRT_*` environment variables and run:
```
% OPENWRT_RELEASE=23.05.3 OPENWRT_ARCH=mips_24kc OPENWRT_TARGET=ath79 OPENWRT_SUBTARGET=generic \
    OPENWRT_SRCDIR=../openwrt make prepare fix-host-symlinks build-kernel build-amneziawg prepare-artifacts
```

Once complete, packages will be available in `${HOME}/openwrt-playground/awgrelease`.

## Building AmneziaWG packages for OpenWrt snapshot

Building for OpenWrt [snapshot](https://openwrt.org/releases/snapshot) (ongoing development branch) works the same way as for stable releases: pass `snapshot` as one of the versions in the `openwrt_versions` input.

The prerequisite is that [ci/target-matrix-config.yaml](ci/target-matrix-config.yaml) contains a `snapshot:` entry defining the desired target(s). Example:
```yaml
snapshot:
  ath79:
    - generic
```

Then trigger the [multibuild-module-artifacts](.github/workflows/multibuild-module-artifacts.yml) workflow with `snapshot` included in the versions list:
```
% gh workflow run multibuild-module-artifacts.yml -f openwrt_versions="snapshot"
```

Note that OpenWrt has migrated from `opkg` to `apk` (Alpine Package Keeper) package manager in snapshots, so artifacts will use the `.apk` extension.

## Creating tagged releases

In order to create new release, a SEMVER tag in a form of `vX.Y.Z` must be created and pushed to the repository.
Corresponding [release workflow](.github/workflows/create-release-from-multibuild.yml) will be automatically triggered.

## Creating opkg feed

The following Makefile targets are available to operate with OpenWrt [package feeds](https://openwrt.org/docs/guide-developer/feeds):
 - `make create-feed`: create new feed from previously built artifacts,
 - `make verify-feed`: verify feed metadata and signatures.

Every tagged release should produce archive(s) with package feed for each unique combination of `OPENWRT_RELEASE`, `OPENWRT_ARCH`, `OPENWRT_TARGET`, and `OPENWRT_SUBTARGET`.
Such archives can be used directly to extract packages for manual installation on target platforms (`.ipk` for releases before 25.12.0, `.apk` for recent releases and snapshots), or be combined into a single feed which can be hosted and accessed externally.

## Miscellaneous

The [openwrt-crossbuild-env](https://github.com/defanator/openwrt-crossbuild-env) tooling uses automated way of obtaining arch and vermagic of a given kernel based on required build parameters (`OPENWRT_RELEASE`, `OPENWRT_TARGET`, `OPENWRT_SUBTARGET`); `make show-env` could be quite handy while debugging various related stuff:

```
% make show-env | grep -- "^OPENWRT"
OPENWRT_RELEASE       23.05.3
OPENWRT_ARCH          mips_24kc
OPENWRT_TARGET        ath79
OPENWRT_SUBTARGET     generic
OPENWRT_VERMAGIC      34a8cffa541c94af8232fe9af7a1f5ba
OPENWRT_BASE_URL      https://downloads.openwrt.org/releases/23.05.3/targets/ath79/generic
OPENWRT_MANIFEST      https://downloads.openwrt.org/releases/23.05.3/targets/ath79/generic/openwrt-23.05.3-ath79-generic.manifest

% OPENWRT_RELEASE=22.03.4 OPENWRT_SUBTARGET=nand make show-env | grep -- "^OPENWRT"
OPENWRT_RELEASE       22.03.4
OPENWRT_ARCH          mips_24kc
OPENWRT_TARGET        ath79
OPENWRT_SUBTARGET     nand
OPENWRT_VERMAGIC      5c9be91b90bda5403fe3a7c4e8ddb26f
OPENWRT_BASE_URL      https://downloads.openwrt.org/releases/22.03.4/targets/ath79/nand
OPENWRT_MANIFEST      https://downloads.openwrt.org/releases/22.03.4/targets/ath79/nand/openwrt-22.03.4-ath79-nand.manifest
```

Output of `make show-env` should be present in GitHub action workflow logs as well.
