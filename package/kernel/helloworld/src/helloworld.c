// src/helloworld.c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

static int __init helloworld_init(void) {
    printk(KERN_INFO "Hello, OpenWrt Kernel World!\n");
    return 0;
}

static void __exit helloworld_exit(void) {
    printk(KERN_INFO "Goodbye, OpenWrt Kernel World!\n");
}

module_init(helloworld_init);
module_exit(helloworld_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("A simple Hello World kernel module");
