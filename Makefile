#!/usr/bin/env make -f

SELF := $(abspath $(lastword $(MAKEFILE_LIST)))
TOPDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
UPPERDIR := $(realpath $(TOPDIR)/../)

OPENWRT_SRCDIR   ?= $(UPPERDIR)/openwrt
AMNEZIAWG_SRCDIR ?= $(TOPDIR)
AMNEZIAWG_DSTDIR ?= $(UPPERDIR)/awgrelease

OPENWRT_RELEASE   ?= 23.05.3
OPENWRT_ARCH      ?= mips_24kc
OPENWRT_TARGET    ?= ath79
OPENWRT_SUBTARGET ?= generic
OPENWRT_VERMAGIC  ?= auto

# for generate-target-matrix
OPENWRT_RELEASES  ?= $(OPENWRT_RELEASE)

GITHUB_SHA        ?= $(shell git rev-parse --short HEAD)
VERSION_STR       ?= $(shell git describe --tags --long --dirty)
POSTFIX           := $(VERSION_STR)_v$(OPENWRT_RELEASE)_$(OPENWRT_ARCH)_$(OPENWRT_TARGET)_$(OPENWRT_SUBTARGET)
FEED_NAME         := amneziawg-opkg-feed-$(GITHUB_REF_NAME)-openwrt-$(OPENWRT_RELEASE)-$(OPENWRT_ARCH)-$(OPENWRT_TARGET)-$(OPENWRT_SUBTARGET)

WORKFLOW_REF      ?= $(shell git rev-parse --abbrev-ref HEAD)

ifneq ($(OPENWRT_RELEASE),snapshot)
OPENWRT_ROOT_URL  ?= https://downloads.openwrt.org/releases
OPENWRT_BASE_URL  ?= $(OPENWRT_ROOT_URL)/$(OPENWRT_RELEASE)/targets/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)
OPENWRT_MANIFEST  ?= $(OPENWRT_BASE_URL)/openwrt-$(OPENWRT_RELEASE)-$(OPENWRT_TARGET)-$(OPENWRT_SUBTARGET).manifest
else
OPENWRT_ROOT_URL  ?= https://downloads.openwrt.org/snapshots
OPENWRT_BASE_URL  ?= $(OPENWRT_ROOT_URL)/targets/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)
OPENWRT_MANIFEST  ?= $(OPENWRT_BASE_URL)/openwrt-$(OPENWRT_TARGET)-$(OPENWRT_SUBTARGET).manifest
endif

NPROC ?= $(shell getconf _NPROCESSORS_ONLN)

ifndef OPENWRT_VERMAGIC
_NEED_VERMAGIC=1
endif

ifeq ($(OPENWRT_VERMAGIC), auto)
_NEED_VERMAGIC=1
endif

ifeq ($(_NEED_VERMAGIC), 1)
ifneq ($(OPENWRT_RELEASE),snapshot)
OPENWRT_VERMAGIC := $(shell curl -fs $(OPENWRT_MANIFEST) | grep -- "^kernel" | sed -e "s,.*\-,,")
else
OPENWRT_VERMAGIC := $(shell curl -fs $(OPENWRT_MANIFEST) | grep -- "^kernel" | sed -e "s,.*\~,," | cut -d '-' -f 1)
endif
endif

ifndef USIGN
ifneq ($(shell usign 2>&1 | grep -i -- "usage: usign"),)
USIGN = usign
endif
endif
USIGN ?= $(error usign not found)

FEED_PATH    ?= $(TOPDIR)/.feed
FEED_SEC_KEY ?= $(error FEED_SEC_KEY unset)
FEED_PUB_KEY ?= $(error FEED_PUB_KEY unset)

help: ## Show help message (list targets)
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[$$()% 0-9a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(SELF)

SHOW_ENV_VARS = \
	SHELL \
	SELF \
	TOPDIR \
	UPPERDIR \
	OPENWRT_SRCDIR \
	AMNEZIAWG_SRCDIR \
	AMNEZIAWG_DSTDIR \
	GITHUB_SHA \
	VERSION_STR \
	POSTFIX \
	FEED_NAME \
	GITHUB_REF_TYPE \
	GITHUB_REF_NAME \
	WORKFLOW_REF \
	OPENWRT_RELEASE \
	OPENWRT_ARCH \
	OPENWRT_TARGET \
	OPENWRT_SUBTARGET \
	OPENWRT_VERMAGIC \
	OPENWRT_BASE_URL \
	OPENWRT_MANIFEST \
	NPROC

show-var-%:
	@{ \
	escaped_v="$(subst ",\",$($*))" ; \
	if [ -n "$$escaped_v" ]; then v="$$escaped_v"; else v="(undefined)"; fi; \
	printf "%-21s %s\n" "$*" "$$v"; \
	}

show-env: $(addprefix show-var-, $(SHOW_ENV_VARS)) ## Show environment details

export-var-%:
	@{ \
	escaped_v="$(subst ",\",$($*))" ; \
	if [ -n "$$escaped_v" ]; then v="$$escaped_v"; else v="(undefined)"; fi; \
	printf "%s=%s\n" "$*" "$$v"; \
	}

export-env: $(addprefix export-var-, $(SHOW_ENV_VARS)) ## Export environment

.venv:
	python3 -m venv $(TOPDIR)/.venv
	$(TOPDIR)/.venv/bin/python3 -m pip install -r $(TOPDIR)/requirements.txt

venv: .venv ## Create virtualenv

.PHONY: generate-target-matrix
generate-target-matrix: .venv ## Generate target matrix of build environments for GitHub CI
	@printf "BUILD_MATRIX=%s" "$$($(TOPDIR)/.venv/bin/python3 $(TOPDIR)/scripts/generate_target_matrix.py $(OPENWRT_RELEASES))"

.PHONY: github-build-cache
github-build-cache: ## Run GitHub workflow to create OpenWrt toolchain and kernel cache (use WORKFLOW_REF to specify branch/tag)
	@{ \
	set -ex ; \
	gh workflow run build-toolchain-cache.yml \
		--ref $(WORKFLOW_REF) \
		-f openwrt_version=$(OPENWRT_RELEASE) \
		-f openwrt_arch=$(OPENWRT_ARCH) \
		-f openwrt_target=$(OPENWRT_TARGET) \
		-f openwrt_subtarget=$(OPENWRT_SUBTARGET) \
		-f openwrt_vermagic=$(OPENWRT_VERMAGIC) ; \
	}

.PHONY: github-build-artifacts
github-build-artifacts: ## Run GitHub workflow to build amneziawg OpenWrt packages (use WORKFLOW_REF to specify branch/tag)
	@{ \
	set -ex ; \
	gh workflow run build-module-artifacts.yml \
		--ref $(WORKFLOW_REF) \
		-f openwrt_version=$(OPENWRT_RELEASE) \
		-f openwrt_arch=$(OPENWRT_ARCH) \
		-f openwrt_target=$(OPENWRT_TARGET) \
		-f openwrt_subtarget=$(OPENWRT_SUBTARGET) \
		-f openwrt_vermagic=$(OPENWRT_VERMAGIC) ; \
	}

$(OPENWRT_SRCDIR):
	@{ \
	set -ex ; \
	git clone https://github.com/openwrt/openwrt.git $@ ; \
	if [ "$(OPENWRT_RELEASE)" != "snapshot" ]; then \
		cd $@ ; \
		git checkout v$(OPENWRT_RELEASE) ; \
	fi ; \
	}

$(OPENWRT_SRCDIR)/feeds.conf: | $(OPENWRT_SRCDIR)
	@{ \
	set -ex ; \
	curl -fsL $(OPENWRT_BASE_URL)/feeds.buildinfo | tee $@ ; \
	}

$(OPENWRT_SRCDIR)/.config: | $(OPENWRT_SRCDIR)
	@{ \
	set -ex ; \
	curl -fsL $(OPENWRT_BASE_URL)/config.buildinfo > $@ ; \
	echo "CONFIG_PACKAGE_kmod-crypto-lib-chacha20=m" >> $@ ; \
	echo "CONFIG_PACKAGE_kmod-crypto-lib-chacha20poly1305=m" >> $@ ; \
	echo "CONFIG_PACKAGE_kmod-crypto-chacha20poly1305=m" >> $@ ; \
	}

.PHONY: build-toolchain
build-toolchain: $(OPENWRT_SRCDIR)/feeds.conf $(OPENWRT_SRCDIR)/.config ## Build OpenWrt toolchain
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	time -p ./scripts/feeds update ; \
	time -p ./scripts/feeds install -a ; \
	time -p make defconfig ; \
	time -p make tools/install -i -j $(NPROC) ; \
	time -p make toolchain/install -i -j $(NPROC) ; \
	}

.PHONY: build-kernel
build-kernel: $(OPENWRT_SRCDIR)/feeds.conf $(OPENWRT_SRCDIR)/.config ## Build OpenWrt kernel
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	time -p make defconfig ; \
	time -p make V=s target/linux/compile -i -j $(NPROC) ; \
	VERMAGIC=$$(cat ./build_dir/target-$(OPENWRT_ARCH)*/linux-$(OPENWRT_TARGET)_$(OPENWRT_SUBTARGET)/linux-*/.vermagic) ; \
	echo "Vermagic: $${VERMAGIC}" ; \
	if [ "$${VERMAGIC}" != "$(OPENWRT_VERMAGIC)" ]; then \
		echo "Vermagic mismatch: $${VERMAGIC}, expected $(OPENWRT_VERMAGIC)" ; \
		exit 1 ; \
	fi ; \
	}

# TODO: this should not be required but actions/cache/save@v4 could not handle circular symlinks with error like this:
# Warning: ELOOP: too many symbolic links encountered, stat '/home/runner/work/amneziawg-openwrt/amneziawg-openwrt/openwrt/staging_dir/toolchain-mips_24kc_gcc-11.2.0_musl/initial/lib/lib'
# Warning: Cache save failed.
.PHONY: purge-circular-symlinks
purge-circular-symlinks:
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	export LC_ALL=C ; \
	for deadlink in $$(find . -follow -type l -printf "" 2>&1 | sed -e "s/find: '\(.*\)': Too many levels of symbolic links.*/\1/"); do \
		echo "deleting dead link: $${deadlink}" ; \
		rm -f "$${deadlink}" ; \
	done ; \
	}

.PHONY: build-amneziawg
build-amneziawg: ## Build amneziawg-openwrt kernel module and packages
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	VERMAGIC=$$(cat ./build_dir/target-$(OPENWRT_ARCH)*/linux-$(OPENWRT_TARGET)_$(OPENWRT_SUBTARGET)/linux-*/.vermagic) ; \
	echo "Vermagic: $${VERMAGIC}" ; \
	if [ "$${VERMAGIC}" != "$(OPENWRT_VERMAGIC)" ]; then \
		echo "Vermagic mismatch: $${VERMAGIC}, expected $(OPENWRT_VERMAGIC)" ; \
		exit 1 ; \
	fi ; \
	echo "src-git awgopenwrt $(AMNEZIAWG_SRCDIR)^$(GITHUB_SHA)" > feeds.conf ; \
	./scripts/feeds update ; \
	./scripts/feeds install -a ; \
	mv .config.old .config ; \
	echo "CONFIG_PACKAGE_kmod-amneziawg=m" >> .config ; \
	echo "CONFIG_PACKAGE_amneziawg-tools=y" >> .config ; \
	echo "CONFIG_PACKAGE_luci-proto-amneziawg=y" >> .config ; \
	make defconfig ; \
	make V=s package/kmod-amneziawg/clean ; \
	make V=s package/kmod-amneziawg/download ; \
	make V=s package/kmod-amneziawg/prepare ; \
	make V=s package/kmod-amneziawg/compile ; \
	make V=s package/luci-proto-amneziawg/clean ; \
	make V=s package/luci-proto-amneziawg/download ; \
	make V=s package/luci-proto-amneziawg/prepare ; \
	make V=s package/luci-proto-amneziawg/compile ; \
	make V=s package/amneziawg-tools/clean ; \
	make V=s package/amneziawg-tools/download ; \
	make V=s package/amneziawg-tools/prepare ; \
	make V=s package/amneziawg-tools/compile ; \
	}

.PHONY: prepare-artifacts
prepare-artifacts: ## Save amneziawg-openwrt artifacts from regular builds
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	mkdir -p $(AMNEZIAWG_DSTDIR)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET) ; \
	cp bin/packages/$(OPENWRT_ARCH)/awgopenwrt/amneziawg-tools_*.ipk $(AMNEZIAWG_DSTDIR)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
	cp bin/packages/$(OPENWRT_ARCH)/awgopenwrt/luci-proto-amneziawg_*.ipk $(AMNEZIAWG_DSTDIR)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
	cp bin/targets/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/packages/kmod-amneziawg_*.ipk $(AMNEZIAWG_DSTDIR)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
	}

.PHONY: check-release
check-release: ## Verify that everything is in place for tagged release
	@{ \
	set -eux ; \
	echo "checking for release" ; \
	if [ "$${GITHUB_REF_TYPE}" != "tag" ]; then \
		echo "ERROR: unsupported GITHUB_REF_TYPE: $${GITHUB_REF_TYPE}" >&2 ; \
		exit 1 ; \
	fi ; \
	if ! echo "$${GITHUB_REF_NAME}" | grep -q -E '^v[0-9]+(\.[0-9]+){2}$$'; then \
		echo "ERROR: tag $${GITHUB_REF_NAME} is NOT a valid semver" >&2 ; \
		exit 1 ; \
	fi ; \
	num_extra_commits="$$(git rev-list "$${GITHUB_REF_NAME}..HEAD" --count)" ; \
	if [ "$${num_extra_commits}" -gt 0 ]; then \
		echo "ERROR: $${num_extra_commits} extra commit(s) detected" >&2 ; \
		exit 1 ; \
	fi ; \
	}

.PHONY: prepare-release
prepare-release: check-release ## Save amneziawg-openwrt artifacts from tagged release
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	mkdir -p $(AMNEZIAWG_DSTDIR) ; \
	FEED_PATH="$(AMNEZIAWG_DSTDIR)/$(FEED_NAME)" $(MAKE) -f $(SELF) create-feed ; \
	FEED_PATH="$(AMNEZIAWG_DSTDIR)/$(FEED_NAME)" $(MAKE) -f $(SELF) verify-feed ; \
	tar -C $(AMNEZIAWG_DSTDIR)/$(FEED_NAME) -czvf $(AMNEZIAWG_DSTDIR)/$(FEED_NAME).tar.gz $(OPENWRT_RELEASE)/ ; \
	}

$(FEED_PATH):
	mkdir -p $@

.PHONY: create-feed
create-feed: | $(FEED_PATH) ## Create package feed
	@{ \
	set -eux ; \
	target_path=$(FEED_PATH)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
	mkdir -p $${target_path} ; \
	for pkg in $$(find $(AMNEZIAWG_DSTDIR)/ -type f -name "*.ipk"); do \
		cp $${pkg} $${target_path}/ ; \
	done ; \
	( cd $${target_path} && $(TOPDIR)/scripts/ipkg-make-index.sh . >Packages && $(USIGN) -S -m Packages -s $(FEED_SEC_KEY) -x Packages.sig && gzip -fk Packages ) ; \
	}

.PHONY: verify-feed
verify-feed: | $(FEED_PATH) ## Verify package feed
	@{ \
	set -eux ; \
	target_path=$(FEED_PATH)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
	cat $${target_path}/Packages ; \
	find $${target_path}/ -type f | sort ; \
	$(USIGN) -V -m $${target_path}/Packages -p $(FEED_PUB_KEY) ; \
	( cd $${target_path} && gunzip -fk Packages.gz ) ; \
	$(USIGN) -V -m $${target_path}/Packages -p $(FEED_PUB_KEY) ; \
	}
