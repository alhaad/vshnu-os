# $@ = target file
# $< = first dependency
# $^ = all dependencies

OUT_DIR := out
ISO := $(OUT_DIR)/vshnu-os.iso
BOOTLOADER_STAGE1 := out/stage1
BOOTLOADER_STAGE2 := out/stage2
KERNEL := out/kernel
KERNEL_ENTRY := out/start.o
RUST_OS := target/x86_64-vshnu-os/release/libvshnu_os.a

.PHONY: all clean

all: $(ISO)

$(BOOTLOADER_STAGE1): bootloader/stage1.asm
	mkdir -p out/
	nasm $< -fbin -o $@

$(BOOTLOADER_STAGE2): bootloader/stage2.asm
	mkdir -p out/
	nasm $< -fbin -o $@

$(RUST_OS): src/lib.rs
	xargo build --release --target x86_64-vshnu-os

$(KERNEL_ENTRY): src/arch/x86_64/start.asm
	mkdir -p out
	nasm $< -felf64 -o $@

$(KERNEL): $(KERNEL_ENTRY) $(RUST_OS)
	x86_64-elf-ld -n --gc-sections -T src/arch/x86_64/linker.ld -o $@ $^ --oformat binary

$(ISO): $(BOOTLOADER_STAGE1) $(BOOTLOADER_STAGE2) $(KERNEL)
	mkdir -p out/cdimg/boot
	cp $^ out/cdimg/boot/
	mkisofs -R -b boot/stage1 -no-emul-boot -boot-load-size 4 -o $@ out/cdimg

run: $(ISO)
	qemu-system-x86_64 -cdrom $< -boot d -s

debug: $(ISO)
	qemu-system-x86_64 -cdrom $< -boot d -s -S

clean:
	cargo clean
	rm -rf out/
