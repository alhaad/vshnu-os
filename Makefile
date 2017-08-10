# $@ = target file
# $< = first dependency
# $^ = all dependencies

IMAGE := out/os-image.bin
BOOTLOADER := out/bootloader.bin
KERNEL := out/kernel.bin
KERNEL_OBJECT := out/kernel.o
KERNEL_ENTRY := out/kernel_entry.o

all: run

$(KERNEL_OBJECT): kernel.c
	mkdir -p out
	x86_64-elf-gcc -ffreestanding -c $< -o $@

$(KERNEL_ENTRY): bootloader/kernel_entry.asm
	mkdir -p out
	nasm $< -felf64 -o $@

$(KERNEL): $(KERNEL_ENTRY) $(KERNEL_OBJECT)
	x86_64-elf-ld -o $@ -Ttext 0x1000 $^ --oformat binary

$(BOOTLOADER): bootloader/main.asm
	mkdir -p out
	nasm $< -f bin -o $@

$(IMAGE): $(BOOTLOADER) $(KERNEL)
	cat $^ > $@

run: $(IMAGE)
	qemu-system-x86_64 -fda $<

clean:
	rm -rf out/
