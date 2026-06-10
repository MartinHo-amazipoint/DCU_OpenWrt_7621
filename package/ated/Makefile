include $(TOPDIR)/rules.mk

PKG_NAME:=ated
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://dev.iopsys.eu/mediatek/ated.git
PKG_SOURCE_VERSION:=master
PKG_MIRROR_HASH:=skip

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/ated
  SECTION:=utils
  CATEGORY:=Base system
  TITLE:=MediaTek ATED Test Tool
  DEPENDS:=+libnl +libpthread
endef

define Build/Configure
	# ATED has no configure step
	true
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) -r ./src $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) \
			-I$(PKG_BUILD_DIR)/src/include \
			-I$(PKG_BUILD_DIR)/src/thread_model \
			-I$(PKG_BUILD_DIR)/src/ctrl_iface" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define Package/ated/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/ated $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,ated))
