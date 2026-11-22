THEOS ?= $(HOME)/theos
TARGET := iphone:clang:latest:16.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = idevelab-core
idevelab-core_FILES = main.m
idevelab-core_INSTALL_PATH = /usr/libexec
idevelab-core_FRAMEWORKS = Foundation
idevelab-core_CFLAGS = -fobjc-arc -Wall -Wextra

include $(THEOS_MAKE_PATH)/tool.mk
