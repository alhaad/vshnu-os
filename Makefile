all: make-bootloader

make-bootloader:
	mkdir -p out
	nasm -fbin bootloader/main.asm -o out/bootloader.bin

run:
	qemu-system-x86_64 out/bootloader.bin

clean:
	rm -rf out/
