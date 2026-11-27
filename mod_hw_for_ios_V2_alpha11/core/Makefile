THEOS ?= $(HOME)/theos
TARGET := iphone:clang:latest:16.0
ARCHS := arm64
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = idevelab-core mod-hw-maintenance-helper mod-hw-manager-pair

idevelab-core_FILES = main.m
idevelab-core_INSTALL_PATH = /usr/libexec
idevelab-core_FRAMEWORKS = Foundation
idevelab-core_CFLAGS = -fobjc-arc -Wall -Wextra

mod-hw-maintenance-helper_FILES = maintenance_helper.m
mod-hw-maintenance-helper_INSTALL_PATH = /usr/bin
mod-hw-maintenance-helper_FRAMEWORKS = Foundation
mod-hw-maintenance-helper_CFLAGS = -fobjc-arc -Wall -Wextra

mod-hw-manager-pair_FILES = manager_pair.m
mod-hw-manager-pair_INSTALL_PATH = /usr/bin
mod-hw-manager-pair_FRAMEWORKS = Foundation
mod-hw-manager-pair_CFLAGS = -fobjc-arc -Wall -Wextra

include $(THEOS_MAKE_PATH)/tool.mk
