# amneziawg-openwrt

This repo is a fork of original [amneziawg-openwrt](https://github.com/amnezia-vpn/amneziawg-openwrt) one with a few extra things intended to help with creating reproducible builds of the AmneziaWG package artifacts for different versions and architectures supported by OpenWrt.

The idea is to keep it up to date with the upstream for all the general sources. All the extra features are basically combined into a top-level [Makefile](Makefile) and a set of GitHub action [workflows](.github/workflows/).

## OpenWRT package feed

Custom OpenWRT package feed with binary packages built using pipelines of this repository is available [here](https://etaoin.shrdlu.club/openwrt-amneziawg/).

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
      github-build-cache      Run GitHub workflow to create OpenWrt toolchain and kernel cache (use WORKFLOW_REF to specify branch/tag)
      github-build-artifacts  Run GitHub workflow to build amneziawg OpenWrt packages (use WORKFLOW_REF to specify branch/tag)
      build-toolchain         Build OpenWrt toolchain
      build-kernel            Build OpenWrt kernel
      build-amneziawg         Build amneziawg-openwrt kernel module and packages
      prepare-artifacts       Save amneziawg-openwrt artifacts from regular builds
      check-release           Verify that everything is in place for tagged release
      prepare-release         Save amneziawg-openwrt artifacts from tagged release
    ```
    It is heavily used by GitHub actions (see below), but it also can be used directly on host platforms to prepare an environment for building OpenWrt packages, including kernel modules.

 2. GitHub action workflows, in particular:
       - [build-toolchain-cache](.github/workflows/build-toolchain-cache.yml) - configures, compiles, and saves all the necessary OpenWrt tools required for building supplementary packages to GitHub cache;
       - [build-module-artifacts](.github/workflows/build-module-artifacts.yml) - builds AmneziaWG packages (.ipk) with the help of a tools created and saved in the GitHub cache by [build-toolchain-cache](.github/workflows/build-toolchain-cache.yml);
       - [create-release](.github/workflows/create-release.yml) - publishes GitHub release from a given tag.

## Creating OpenWrt toolchain and kernel cache

Note that this process could take about 2 hours on a [default GitHub hosted runner](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners#standard-github-hosted-runners-for-public-repositories). For using GitHub actions powered methods, you will need to create your own fork of this repository first.

### With GitHub actions from UI

Go to the Actions menu, select "build toolchain cache" workflow on the left, click on the "Run workflow" drop-down on the right. Enter all the details for target OpenWrt release and architecture, and press "Run workflow" button to initiate the job:

![build-toolchain-cache screenshot](docs/build-toolchain-cache1.png)

### With GitHub actions from CLI

Use the `github-build-cache` target (do not forget to set your own build details through `OPENWRT_*` environment variables):
```
% OPENWRT_RELEASE=23.05.4 OPENWRT_ARCH=mips_24kc OPENWRT_TARGET=ath79 OPENWRT_SUBTARGET=generic make github-build-cache
```

### Verifying created caches

Go to the Actions menu and select Management - Caches on the left:

![toolchain caches screenshot](docs/build-toolchain-cache2.png)

Refer to the workflow logs to figure out what went wrong in case if a desired cache has not been created during the run.

### Manually on a host VM/instance

Run this:
```
% mkdir -p ${HOME}/openwrt-playground
% cd ${HOME}/openwrt-playground
% git clone https://github.com/defanator/amneziawg-openwrt.git
% cd amneziawg-openwrt
% OPENWRT_RELEASE=23.05.4 OPENWRT_ARCH=mips_24kc OPENWRT_TARGET=ath79 OPENWRT_SUBTARGET=generic make build-toolchain build-kernel
```

Do not forget to set your own build details. Once make invocation is complete, toolchain and kernel should be available in `${HOME}/openwrt-playground/openwrt`.

## Building AmneziaWG packages

Note that toolchain cache must exist in order for these steps to complete (in case if GitHub actions are used). Building AmneziaWG packages should not take longer than 10 minutes if corresponding toolchain/kernel cache is available.

### With GitHub actions from UI

Go to the Actions menu, select "build module artifacts" workflow on the left, click on the "Run workflow" drop-down on the right. Enter all the details for target OpenWrt release and architecture, and press "Run workflow" button to initiate the job:

![build-module-artifacts screenshot](docs/build-module-artifacts1.png)

### With GitHub actions from CLI

Use the `github-build-artifacts` target (do not forget to set your own build details through `OPENWRT_*` environment variables):
```
% OPENWRT_RELEASE=23.05.4 OPENWRT_ARCH=mips_24kc OPENWRT_TARGET=ath79 OPENWRT_SUBTARGET=generic make github-build-artifacts
```

### Locating the artifacts

Go to the workflow summary page and look for "Artifacts produced during runtime" section in the bottom:

![build-module-artifacts results screenshot](docs/build-module-artifacts2.png)

### Manually on a host VM/instance

Make sure you completed toolchain and kernel builds as described above, then run this:
```
% cd ${HOME}/openwrt-playground/amneziawg-openwrt
% OPENWRT_RELEASE=23.05.4 OPENWRT_ARCH=mips_24kc OPENWRT_TARGET=ath79 OPENWRT_SUBTARGET=generic make build-amneziawg prepare-artifacts
```

Do not forget to set your own build details. Once make invocation is complete, packages should be available in `${HOME}/openwrt-playground/awgrelease`.

## Building AmneziaWG packages for OpenWrt snapshot

This section describes how existing workflows can be used to build AmneziaWG packages for OpenWrt [snapshot](https://openwrt.org/releases/snapshot) (ongoing development branch).

### Building package artifacts for OpenWrt snapshot: general steps

These steps must be performed in a given order:

1. Run the [build toolchain cache](.github/workflows/build-toolchain-cache.yml) workflow with the following inputs modified:

    1. "OpenWrt version" must be set to `snapshot`,
    2. "OpenWrt snapshot git ref" must be set either to `main` (default [upstream branch](https://github.com/openwrt/openwrt/branches)), or to a particular commit ref from [upstream history](https://github.com/openwrt/openwrt/commits/main/).

    Example:
    ![build-toolchain-cache for snapshot screenshot](docs/build-toolchain-cache-snapshot.png)

2. Run the [build module artifacts](.github/workflows/build-module-artifacts.yml) workflow with the following inputs modified:

    1. "OpenWrt version" must be set to `snapshot`,
    2. "OpenWrt snapshot git ref" must be set to the same value as in the 1st step of building toolchain cache. Note that if you were using branch name while building toolchain cache, it's worth to use particular commit SHA from that job in this step (commit SHA can be found in job log for the "checkout openwrt (snapshot)" step - see e.g. [this one](https://github.com/defanator/amneziawg-openwrt/actions/runs/13474586977/job/37652166474#step:4:165) for the reference): this way the building environment for module/packages should be in consistent shape with previous one where toolchain/kernel were first created.

    Example:
    ![build-module-artifacts for snapshot screenshot](docs/build-module-artifacts-snapshot.png)

3. Collect the artifacts - e.g. for [this run](https://github.com/defanator/amneziawg-openwrt/actions/runs/13480463738) you would get the following data:
   ```
   snapshot/ath79/generic/amneziawg-tools-1.0.20241018-r1.apk
   snapshot/ath79/generic/kmod-amneziawg-6.6.78.1.0.20241112-r1.apk
   snapshot/ath79/generic/luci-proto-amneziawg-0.0.1-r1.apk
   snapshot/ath79/generic/packages.adb
   snapshot/ath79/generic/packages.adb.txt
   ```

(Note that OpenWrt has migrated from `opkg` to `apk` (Alpine Package Keeper) package manager in snapshots.)

### Debugging issues related to building for OpenWrt snapshot

Under the hood the workflows run the same set of Makefile targets to achieve the goal, so in case of any issues you may refer to workflow logs and try to reproduce a failure in a manual build (follow the above guidance on how to build toolchain, kernel, and packages on VMs).

## Creating tagged releases

In order to create new release, a SEMVER tag in a form of `vX.Y.Z` must be created and pushed to the repository.
Corresponding [release workflow](.github/workflows/create-release.yml) will be automatically triggered.

## Creating opkg feed

The following Makefile targets are available to operate with OpenWrt [package feeds](https://openwrt.org/docs/guide-developer/feeds):
 - `make create-feed`: create new feed from previously built artifacts,
 - `make verify-feed`: verify feed metadata and signatures.

Every tagged release should produce archive(s) with opkg feed for each unique combination of `OPENWRT_RELEASE`, `OPENWRT_ARCH`, `OPENWRT_TARGET`, and `OPENWRT_SUBTARGET`.
Such archives can be used directly to extract `.ipk` packages for manual installation on target platforms, or be combined into a single feed which can be hosted and accessed externally (TODO: add an example of how to configure `/etc/opkg/customfeeds.conf`).

## Miscellaneous

This tooling uses automated way of obtaining vermagic of a given kernel based on required build parameters (`OPENWRT_RELEASE`, `OPENWRT_ARCH`, `OPENWRT_TARGET`, `OPENWRT_SUBTARGET`); `make show-env` could be quite handy while debugging various related stuff:

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
