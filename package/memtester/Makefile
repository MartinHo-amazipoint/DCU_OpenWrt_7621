include $(TOPDIR)/rules.mk

PKG_NAME:=memtester
PKG_VERSION:=4.5.0
PKG_RELEASE:=1

PKG_SOURCE:=memtester-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=http://pyropus.ca/software/memtester/
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/memtester
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=memtester - userspace memory tester
  DEPENDS:=+libc
endef

define Package/memtester/description
 memtester is a userspace utility for testing the memory subsystem.
 It writes test patterns to memory and verifies correctness.
endef

# No configure step needed
define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		$(PKG_BUILD_DIR)/memtester.c $(PKG_BUILD_DIR)/tests.c -o $(PKG_BUILD_DIR)/memtester
endef

define Package/memtester/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/memtester $(1)/usr/bin/
endef

$(eval $(call BuildPackage,memtester))
