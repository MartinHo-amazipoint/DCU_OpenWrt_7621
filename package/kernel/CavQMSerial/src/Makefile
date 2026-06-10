obj-m += CavQMSerial_mod.o
CavQMSerial_mod-objs := CavQMSerial.o

all:
	make -C $(KERNEL_SRC) M=$(PWD) modules

clean:
	make -C $(KERNEL_SRC) M=$(PWD) clean
