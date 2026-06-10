include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=helloworld
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define KernelPackage/helloworld
  SUBMENU:=Other modules
  TITLE:=Hello World test module
  FILES:=$(PKG_BUILD_DIR)/helloworld.ko
  AUTOLOAD:=$(call AutoLoad,50,helloworld)
endef

define KernelPackage/helloworld/description
  Simple Hello World kernel module
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

$(eval $(call KernelPackage,helloworld))
