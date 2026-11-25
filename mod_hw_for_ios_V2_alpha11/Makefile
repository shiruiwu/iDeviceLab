ARCHS = arm64
TARGET = iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = mod_hw_for_ios
mod_hw_for_ios_FILES = src/mobile_gestalt/mobile_gestalt.m src/cydia_substrate_hook/HookUtil.m src/captain_hook/hook.mm
mod_hw_for_ios_CFLAGS = -Wno-error=deprecated-declarations -fno-objc-arc -I$(THEOS_PROJECT_DIR)/src -I$(THEOS_PROJECT_DIR)/src/third_party
mod_hw_for_ios_CCFLAGS = -std=c++17 -fno-objc-arc -I$(THEOS_PROJECT_DIR)/src -I$(THEOS_PROJECT_DIR)/src/third_party
mod_hw_for_ios_FRAMEWORKS = Foundation CoreFoundation CoreTelephony Security SystemConfiguration
mod_hw_for_ios_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
