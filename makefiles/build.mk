SHELL := /usr/bin/env bash
.DEFAULT_GOAL := all

TARGET ?= msdos
FUJINET_NIO_LIB ?= ../fujinet-nio-lib

include makefiles/targets.mk

FNSVC_LIST_MAX_PAYLOAD ?= 420
ifeq ($(TARGET),bbc)
FNSVC_LIST_MAX_PAYLOAD := 250
endif

SRC_DIR := src
STATE_MODEL_bbc := external
STATE_MODEL := $(if $(STATE_MODEL_$(TARGET)),$(STATE_MODEL_$(TARGET)),embedded)
APP_INCLUDE_DIR := include/common
CONFIG_NIO_INCLUDE_DIR := include
PLATFORM_INCLUDE_DIR := include/platform/$(PLATFORM)
NIO_INCLUDE_DIR := $(FUJINET_NIO_LIB)/include
BUILD_DIR ?= build
TARGET_BUILD_DIR := $(BUILD_DIR)/$(TARGET)
OBJ_DIR := $(TARGET_BUILD_DIR)/obj
BIN_DIR := $(TARGET_BUILD_DIR)/bin
DISK_DIR := $(TARGET_BUILD_DIR)/disk

CONFIG_NIO_PROGRAMS := config-nio
SUPPORT_PROGRAMS_bbc := keycode
SUPPORT_PROGRAMS := $(SUPPORT_PROGRAMS_$(TARGET))
PROGRAMS := $(CONFIG_NIO_PROGRAMS) $(SUPPORT_PROGRAMS)
PROGRAM_BINS := $(PROGRAMS:%=$(BIN_DIR)/%$(PROGRAM_EXT))

SUPPORT_OBJS := $(SUPPORT_PROGRAMS:%=$(OBJ_DIR)/$(SRC_DIR)/support/%.o)

ifeq ($(COMPILER_FAMILY),wcc)
include makefiles/compiler-wcc.mk
else ifeq ($(COMPILER_FAMILY),cc65)
include makefiles/compiler-cc65.mk
else ifeq ($(COMPILER_FAMILY),gcc)
include makefiles/compiler-gcc.mk
else
$(error Unknown compiler family '$(COMPILER_FAMILY)' for TARGET=$(TARGET))
endif

CONFIG_NIO_SRCS := \
	$(wildcard $(SRC_DIR)/*.c) \
	$(wildcard $(SRC_DIR)/common/*.c) \
	$(wildcard $(SRC_DIR)/model/$(STATE_MODEL)/*.c) \
	$(wildcard $(SRC_DIR)/platform/$(PLATFORM)/*.c)
CONFIG_NIO_ASM_SRCS := \
	$(wildcard $(SRC_DIR)/common/*.s) \
	$(wildcard $(SRC_DIR)/model/$(STATE_MODEL)/*.s) \
	$(wildcard $(SRC_DIR)/platform/$(PLATFORM)/*.s)
CONFIG_NIO_OBJS := $(patsubst %.c,$(OBJ_DIR)/%.o,$(CONFIG_NIO_SRCS))
CONFIG_NIO_ASM_OBJS := $(patsubst %.s,$(OBJ_DIR)/%.o,$(CONFIG_NIO_ASM_SRCS))
DEPENDS := $(SUPPORT_OBJS:.o=.d) $(CONFIG_NIO_OBJS:.o=.d)

ifeq ($(TARGET),bbc)
CONFIG_NIO_BBC_TEMPLATE_INPUTS := \
	bbc/assets/config-nio-templates/CNHOSTS \
	bbc/assets/config-nio-templates/CNBROW \
	bbc/assets/config-nio-templates/CNSLOTS \
	bbc/config_nio_layout.json \
	bbc/scripts/generate_config_nio_templates.py
CONFIG_NIO_BBC_GENERATED := \
	$(SRC_DIR)/platform/$(PLATFORM)/config_nio_template_data.s \
	$(SRC_DIR)/platform/$(PLATFORM)/config_nio_layout.h

$(CONFIG_NIO_BBC_GENERATED): $(CONFIG_NIO_BBC_TEMPLATE_INPUTS)
	python3 bbc/scripts/generate_config_nio_templates.py

$(OBJ_DIR)/$(SRC_DIR)/platform/$(PLATFORM)/config_nio_template_data.o: $(CONFIG_NIO_BBC_GENERATED)
$(OBJ_DIR)/$(SRC_DIR)/platform/$(PLATFORM)/config_nio_ui.o: $(SRC_DIR)/platform/$(PLATFORM)/config_nio_layout.h
endif

ifeq ($(TARGET),msdos)
PDCURSES_DIR ?= ../PDCurses
PDCURSES_MSDOS_LIB ?= ../../build/pdcurses/msdos-small/pdcurses.lib
CONFIG_NIO_LIBS := $(PDCURSES_MSDOS_LIB)
CONFIG_NIO_DEPS := $(PDCURSES_MSDOS_LIB)
CFLAGS += -i=$(PDCURSES_DIR)
endif

ifeq ($(TARGET),bbc)
include makefiles/config-nio-bbc.mk
endif

.PHONY: all clean $(PROGRAMS)
.SECONDARY: $(SUPPORT_OBJS) $(CONFIG_NIO_OBJS) $(CONFIG_NIO_ASM_OBJS)

all: $(PROGRAM_BINS)

$(PROGRAMS): %: $(BIN_DIR)/%$(PROGRAM_EXT)

-include $(DEPENDS)

$(NIO_LIB_FILE):
	$(MAKE) -C $(FUJINET_NIO_LIB) $(NIO_LIB_TARGET)

$(OBJ_DIR)/%.o: %.c | $(OBJ_DIR)
	@mkdir -p $(dir $@)
	$(call compile_c)

$(OBJ_DIR)/%.o: %.s | $(OBJ_DIR)
	@mkdir -p $(dir $@)
	ca65 -t $(TARGET) $(ASMFLAGS) -I /home/markf/dev/nio/fujinet-nio-workspace/repos/cc65/libsrc/bbc -o $@ $<

$(BIN_DIR)/keycode$(PROGRAM_EXT): $(OBJ_DIR)/$(SRC_DIR)/support/keycode.o | $(BIN_DIR)
	$(call link_program)

$(BIN_DIR)/config-nio$(PROGRAM_EXT): $(CONFIG_NIO_OBJS) $(CONFIG_NIO_ASM_OBJS) $(CONFIG_NIO_DEPS) $(NIO_LIB_FILE) | $(BIN_DIR)
	$(call link_program)

ifeq ($(TARGET),bbc)
BBC_CONFIG_NIO_START_ADDRESS ?= 0x1900
BBC_CONFIG_NIO_HIMEM ?= 0x7C00
$(BIN_DIR)/config-nio$(PROGRAM_EXT): CFLAGS += -DCONFIG_NIO_EXTERNAL_TABLE_STATE
$(BIN_DIR)/config-nio$(PROGRAM_EXT): CFLAGS += -DFNSVC_MOUNT_URI_MAX=160 -DFNSVC_MOUNT_MODE_MAX=4
ifeq ($(BBC_CONFIG_NIO_SHADOW_MODE),1)
$(BIN_DIR)/config-nio$(PROGRAM_EXT): CFLAGS += -DCONFIG_NIO_BBC_SHADOW_MODE
endif
ifeq ($(BBC_CONFIG_NIO_XRAM_TABLES),1)
$(BIN_DIR)/config-nio$(PROGRAM_EXT): CFLAGS += -DCONFIG_NIO_BBC_XRAM_TABLES
$(CONFIG_NIO_ASM_OBJS): ASMFLAGS += -DCONFIG_NIO_BBC_XRAM_TABLES
endif
$(BIN_DIR)/config-nio$(PROGRAM_EXT): LDFLAGS := -t $(TARGET) --start-addr $(BBC_CONFIG_NIO_START_ADDRESS) -Wl -D,__HIMEM__=$(BBC_CONFIG_NIO_HIMEM)
endif

$(OBJ_DIR):
	mkdir -p $@

$(BIN_DIR):
	mkdir -p $@

$(DISK_DIR):
	mkdir -p $@

clean:
	rm -rf $(TARGET_BUILD_DIR)
