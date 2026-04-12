#!/usr/bin/env make -f

SELF := $(abspath $(lastword $(MAKEFILE_LIST)))
TOPDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
UPPERDIR := $(realpath $(TOPDIR)/../)

OPENWRT_CROSSBUILD_ENV_DIR ?= $(UPPERDIR)/openwrt-crossbuild-env

AMNEZIAWG_SRCDIR ?= $(TOPDIR)
AMNEZIAWG_DSTDIR ?= $(UPPERDIR)/awgrelease

GITHUB_SHA       ?= $(shell git rev-parse --short HEAD)
VERSION_STR      ?= $(shell git describe --tags --long --dirty)
WORKFLOW_REF     ?= $(shell git rev-parse --abbrev-ref HEAD)

NPROC ?= $(shell getconf _NPROCESSORS_ONLN)

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
	OPENWRT_RELEASE_NUM \
	OPENWRT_ARCH \
	OPENWRT_TARGET \
	OPENWRT_SUBTARGET \
	OPENWRT_VERMAGIC \
	OPENWRT_SNAPSHOT_REF \
	OPENWRT_BASE_URL \
	OPENWRT_MANIFEST \
	OPENWRT_PKG_EXT \
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

-include $(OPENWRT_CROSSBUILD_ENV_DIR)/Makefile.crossbuild
OPENWRT_SRCDIR ?= $(error OPENWRT_SRCDIR is not defined - might be an issue with including Makefile.crossbuild)
OPENWRT_PKG_EXT ?= $(error OPENWRT_PKG_EXT is not defined - might be an issue with including Makefile.crossbuild)

POSTFIX    := $(VERSION_STR)_v$(OPENWRT_RELEASE)_$(OPENWRT_ARCH)_$(OPENWRT_TARGET)_$(OPENWRT_SUBTARGET)
FEED_NAME  := amneziawg-opkg-feed-$(VERSION_STR)-openwrt-$(OPENWRT_RELEASE)-$(OPENWRT_ARCH)-$(OPENWRT_TARGET)-$(OPENWRT_SUBTARGET)

APK := $(realpath $(OPENWRT_SRCDIR)/staging_dir/host/bin/apk)

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
	cp bin/packages/$(OPENWRT_ARCH)/awgopenwrt/amneziawg-tools*$(OPENWRT_PKG_EXT) $(AMNEZIAWG_DSTDIR)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
	cp bin/packages/$(OPENWRT_ARCH)/awgopenwrt/luci-proto-amneziawg*$(OPENWRT_PKG_EXT) $(AMNEZIAWG_DSTDIR)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
	cp bin/targets/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/packages/kmod-amneziawg*$(OPENWRT_PKG_EXT) $(AMNEZIAWG_DSTDIR)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/ ; \
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

.PHONY: create-feed-archive
create-feed-archive: ## Create archive of a package feed
	@{ \
	set -eux ; \
	cd $(OPENWRT_SRCDIR) ; \
	mkdir -p $(AMNEZIAWG_DSTDIR) ; \
	FEED_PATH="$(AMNEZIAWG_DSTDIR)/$(FEED_NAME)" $(MAKE) -f $(SELF) create-feed ; \
	FEED_PATH="$(AMNEZIAWG_DSTDIR)/$(FEED_NAME)" $(MAKE) -f $(SELF) verify-feed ; \
	tar -C $(AMNEZIAWG_DSTDIR)/$(FEED_NAME) -czvf $(AMNEZIAWG_DSTDIR)/$(FEED_NAME).tar.gz $(OPENWRT_RELEASE)/ ; \
	}

.PHONY: prepare-release
prepare-release: check-release create-feed-archive ## Save amneziawg-openwrt artifacts from tagged release

$(FEED_PATH):
	mkdir -p $@

.PHONY: create-feed-ipk
create-feed-ipk: | $(FEED_PATH)
	@{ \
	set -eux ; \
	target_path=$(FEED_PATH)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET) ; \
	mkdir -p $${target_path} ; \
	for pkg in $$(find $(AMNEZIAWG_DSTDIR)/ -type f -name "*$(OPENWRT_PKG_EXT)"); do \
		cp $${pkg} $${target_path}/ ; \
	done ; \
	( cd $${target_path} && $(TOPDIR)/scripts/ipkg-make-index.sh . >Packages && $(USIGN) -S -m Packages -s $(FEED_SEC_KEY) -x Packages.sig && gzip -fk Packages ) ; \
	cat $${target_path}/Packages ; \
	}

.PHONY: verify-feed-ipk
verify-feed-ipk: | $(FEED_PATH)
	@{ \
	set -eux ; \
	target_path=$(FEED_PATH)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET) ; \
	cat $${target_path}/Packages ; \
	find $${target_path}/ -type f | sort ; \
	$(USIGN) -V -m $${target_path}/Packages -p $(FEED_PUB_KEY) ; \
	( cd $${target_path} && gunzip -fk Packages.gz ) ; \
	$(USIGN) -V -m $${target_path}/Packages -p $(FEED_PUB_KEY) ; \
	}

.PHONY: create-feed-apk
create-feed-apk:
	@{ \
	set -eux ; \
	export APK="$(APK)" ; \
	$${APK} --version ; \
	target_path=$(FEED_PATH)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET) ; \
	mkdir -p $${target_path} ; \
	for pkg in $$(find $(AMNEZIAWG_DSTDIR)/ -type f -name "*$(OPENWRT_PKG_EXT)"); do \
		cp $${pkg} $${target_path}/ ; \
	done ; \
	$(TOPDIR)/scripts/apk-make-index.sh create "$${target_path}" ; \
	$(TOPDIR)/scripts/apk-make-index.sh dump "$${target_path}" ; \
	}

.PHONY: verify-feed-apk
verify-feed-apk:
	@{ \
	set -eux ; \
	export APK="$(APK)" ; \
	$${APK} --version ; \
	target_path=$(FEED_PATH)/$(OPENWRT_RELEASE)/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET) ; \
	$(TOPDIR)/scripts/apk-make-index.sh dump "$${target_path}" ; \
	$(TOPDIR)/scripts/apk-make-index.sh verify "$${target_path}" ; \
	}

ifeq ($(OPENWRT_PKG_EXT),.ipk)
.PHONY: create-feed
create-feed: create-feed-ipk ## Create package feed

.PHONY: verify-feed
verify-feed: verify-feed-ipk ## Verify package feed
else
.PHONY: create-feed
create-feed: create-feed-apk

.PHONY: verify-feed
verify-feed: verify-feed-apk
endif
