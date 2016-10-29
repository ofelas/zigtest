# zigos
Mimicking the brilliant Blog OS from [Philipp Oppermann's
blog](http://os.phil-opp.com/) a fair amount of well described
details can be found there.

Inspired by [nimkernel](https://github.com/dom96/nimkernel)

![Zig OS](zigos.png)

```
shell$ make clean; make
shell$ qemu-system-x86_64 -cdrom zigos-x86_64.iso -s -S -no-reboot
shell$ gdb ./build/bin/kernel-x86_64.bin -ex "target remote :1234"
```

Some required packages on Linux (this on Linux Mint 18)
```
sudo apt-get install nasm
sudo apt install xorriso
sudo apt-get install grub-pc-bin
sudo apt-get install qemu
```
