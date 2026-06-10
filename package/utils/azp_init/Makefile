include $(TOPDIR)/rules.mk

PKG_NAME:=azp_init
PKG_VERSION:=$(AUTORELEASE)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=$(PKG_NAME)
endef

# Do not remove this empty Build/Compile section, else make error occurred.
define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

