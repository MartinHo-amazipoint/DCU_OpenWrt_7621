include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=CavQMSerial
PKG_VERSION:=1.0.0.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define KernelPackage/CavQMSerial
  SUBMENU:=USB Support
  TITLE:=Cavli QM Serial Kernel Module
  FILES:=$(PKG_BUILD_DIR)/CavQMSerial_mod.ko
  AUTOLOAD:=$(call AutoLoad,50,CavQMSerial_mod)
  DEPENDS:=+kmod-usb-serial
endef

define KernelPackage/CavQMSerial/description
  Kernel module for Cavli QM Serial devices.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
	touch $(PKG_BUILD_DIR)/.prepared
endef

define Build/Compile
	$(MAKE) -C "$(LINUX_DIR)" \
		ARCH="$(LINUX_KARCH)" \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		M="$(PKG_BUILD_DIR)" \
		modules
endef

$(eval $(call KernelPackage,CavQMSerial))
