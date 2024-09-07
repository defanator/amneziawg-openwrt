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
#OPENWRT_VERMAGIC  ?= 34a8cffa541c94af8232fe9af7a1f5ba
OPENWRT_VERMAGIC  ?= auto

GITHUB_SHA        ?= $(shell git rev-parse --short HEAD)
VERSION_STR       ?= $(shell git describe --tags --long --dirty)
POSTFIX           := $(VERSION_STR)_v$(OPENWRT_RELEASE)_$(OPENWRT_ARCH)_$(OPENWRT_TARGET)_$(OPENWRT_SUBTARGET)

OPENWRT_ROOT_URL  ?= https://downloads.openwrt.org/releases
OPENWRT_BASE_URL  ?= $(OPENWRT_ROOT_URL)/$(OPENWRT_RELEASE)/targets/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)
OPENWRT_MANIFEST  ?= $(OPENWRT_BASE_URL)/openwrt-$(OPENWRT_RELEASE)-$(OPENWRT_TARGET)-$(OPENWRT_SUBTARGET).manifest

NPROC ?= $(shell getconf _NPROCESSORS_ONLN)

ifndef OPENWRT_VERMAGIC
_NEED_VERMAGIC=1
endif

ifeq ($(OPENWRT_VERMAGIC), auto)
_NEED_VERMAGIC=1
endif

ifeq ($(_NEED_VERMAGIC), 1)
OPENWRT_VERMAGIC := $(shell curl -fs $(OPENWRT_MANIFEST) | grep -- "^kernel" | sed -e "s,.*\-,,")
endif

help: ## Show help message (list targets)
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[$$()% 0-9a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(SELF)

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
	NPROC \
	OPENWRT_RELEASE \
	OPENWRT_ARCH \
	OPENWRT_TARGET \
	OPENWRT_SUBTARGET \
	OPENWRT_VERMAGIC \
	OPENWRT_BASE_URL \
	OPENWRT_MANIFEST

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

$(OPENWRT_SRCDIR):
	@{ \
	set -ex ; \
	git clone https://github.com/openwrt/openwrt.git $@ ; \
	}

.PHONY: fetch-openwrt
fetch-openwrt: | $(OPENWRT_SRCDIR) ## Clone OpenWrt sources of a given release
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	git checkout v$(OPENWRT_RELEASE) ; \
	}

$(OPENWRT_SRCDIR)/feeds.conf: fetch-openwrt
	@{ \
	set -ex ; \
	curl -fsL $(OPENWRT_BASE_URL)/feeds.buildinfo | tee $@ ; \
	}

$(OPENWRT_SRCDIR)/.config: fetch-openwrt
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
	ls -l staging_dir/toolchain-mips_24kc_gcc-11.2.0_musl/initial/lib ; \
	ls -l staging_dir/toolchain-mips_24kc_gcc-11.2.0_musl/initial/lib/lib ; \
	}

.PHONY: build-kernel
build-kernel: $(OPENWRT_SRCDIR)/feeds.conf $(OPENWRT_SRCDIR)/.config ## Build OpenWrt kernel
	@{ \
	set -ex ; \
	cd $(OPENWRT_SRCDIR) ; \
	time -p make V=s target/linux/compile -i -j $(NPROC) ; \
	VERMAGIC=$$(cat ./build_dir/target-$(OPENWRT_ARCH)*/linux-$(OPENWRT_TARGET)_$(OPENWRT_SUBTARGET)/linux-*/.vermagic) ; \
	echo "Vermagic: $${VERMAGIC}" ; \
	if [ "$${VERMAGIC}" != "$(OPENWRT_VERMAGIC)" ]; then \
		echo "Vermagic mismatch: $${VERMAGIC}, expected $(OPENWRT_VERMAGIC)" ; \
		exit 1 ; \
	fi ; \
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
	mkdir -p $(AMNEZIAWG_DSTDIR) ; \
	cp bin/packages/$(OPENWRT_ARCH)/awgopenwrt/amneziawg-tools_*.ipk $(AMNEZIAWG_DSTDIR)/amneziawg-tools_$(POSTFIX).ipk ; \
	cp bin/packages/$(OPENWRT_ARCH)/awgopenwrt/luci-proto-amneziawg_*.ipk $(AMNEZIAWG_DSTDIR)/luci-proto-amneziawg_$(POSTFIX).ipk ; \
	cp bin/targets/$(OPENWRT_TARGET)/$(OPENWRT_SUBTARGET)/packages/kmod-amneziawg_*.ipk $(AMNEZIAWG_DSTDIR)/kmod-amneziawg_$(POSTFIX).ipk ; \
	}
