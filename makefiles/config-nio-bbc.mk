CONFIG_NIO_BBC_ASSET_DIR ?= bbc/assets
CONFIG_NIO_BBC_STAGE_DIR ?= $(DISK_DIR)/config-nio

.PHONY: config-nio-bbc-stage config-nio-master-stage

define CONFIG_NIO_STAGE_PROFILE
	$(MAKE) -f makefiles/build.mk \
		TARGET=bbc \
		BUILD_DIR="$(BUILD_DIR)/config-nio-$(1)" \
		FUJINET_NIO_LIB="$(FUJINET_NIO_LIB)" \
		BBC_CONFIG_NIO_START_ADDRESS="$(2)" \
		BBC_CONFIG_NIO_HIMEM="$(3)" \
		BBC_CONFIG_NIO_SHADOW_MODE="$(4)" \
		BBC_CONFIG_NIO_XRAM_TABLES="$(5)" \
		config-nio keycode
	rm -rf "$(CONFIG_NIO_BBC_STAGE_DIR)"
	mkdir -p "$(CONFIG_NIO_BBC_STAGE_DIR)"
	cp "$(BUILD_DIR)/config-nio-$(1)/bbc/bin/config-nio" "$(CONFIG_NIO_BBC_STAGE_DIR)/CONFNIO"
	cp "$(CONFIG_NIO_BBC_ASSET_DIR)/config-nio-$(1)/CONFNIO.inf" "$(CONFIG_NIO_BBC_STAGE_DIR)/CONFNIO.inf"
	cp "$(BUILD_DIR)/config-nio-$(1)/bbc/bin/keycode" "$(CONFIG_NIO_BBC_STAGE_DIR)/KEYCODE"
	cp "$(CONFIG_NIO_BBC_ASSET_DIR)/KEYCODE.inf" "$(CONFIG_NIO_BBC_STAGE_DIR)/KEYCODE.inf"
endef

config-nio-bbc-stage:
	$(call CONFIG_NIO_STAGE_PROFILE,bbc,0x1900,0x7C00,0,0)

config-nio-master-stage:
	$(call CONFIG_NIO_STAGE_PROFILE,master,0x0E00,0x8000,1,1)
