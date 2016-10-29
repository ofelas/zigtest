# Copyright 2016 Philipp Oppermann. See the README.md
# file at the top-level directory of this distribution.
#
# Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
# http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
# <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
# option. This file may not be copied, modified, or distributed
# except according to those terms.

ZIG ?= ~/projects/REPOS/zig/build/bin/zig

arch ?= x86_64
target ?= $(arch)-blog_os
kernel := kernel-$(arch).bin
zkernel := build/bin/kernel-$(arch).bin
iso := zigos-$(arch).iso

rust_os := target/$(target)/debug/libblog_os.a
linker_script := arch/$(arch)/linker.ld
grub_cfg := arch/$(arch)/grub.cfg
assembly_source_files := $(wildcard arch/$(arch)/*.asm)
assembly_object_files := $(patsubst arch/$(arch)/%.asm, \
	build/arch/$(arch)/%.o, $(assembly_source_files))

.PHONY: all clean run debug iso cargo gdb

all: zigos # $(kernel)

# @cargo clean
clean:
	@rm -rf build

run: $(iso)
	@qemu-system-x86_64 -cdrom $(iso) -s

debug: $(iso)
	@qemu-system-x86_64 -cdrom $(iso) -s -S

gdb:
	@rust-os-gdb/bin/rust-gdb "build/kernel-x86_64.bin" -ex "target remote :1234"

iso: $(iso)

# $(iso): $(kernel) $(grub_cfg)
# 	@mkdir -p build/isofiles/boot/grub
# 	@cp $(kernel) build/isofiles/boot/kernel.bin
# 	@cp $(grub_cfg) build/isofiles/boot/grub
# 	@grub-mkrescue -o $(iso) build/isofiles 2> /dev/null
# 	@rm -r build/isofiles

# $(kernel): cargo $(rust_os) $(assembly_object_files) $(linker_script)
# 	@ld -n --gc-sections -T $(linker_script) -o $(kernel) $(assembly_object_files) $(rust_os)

cargo:
	@cargo build --target $(target)

################################################################################
# Does not compile, but not yet needed...
# TODO
# Aborted
# ~/projects/REPOS/zig/build/bin/zig build --export obj --name compiler_rt compiler_rt.zig

zig_source_files := zmain.zig builtin.zig
zig_object_files := $(patsubst %.zig, build/obj/%.o,$(zig_source_files))

build/obj build/bin:
	mkdir -p $(@)

build/obj/%.o: src/%.zig | build/obj
	$(ZIG) build --export obj --output $(@) --name $(notdir $(subst .o,,$(@))) $(<)

$(zkernel): $(assembly_object_files) $(zig_object_files) | build/bin
	ld -n -T $(linker_script) -o $(zkernel) $(^) # compiler_rt.o

$(iso): $(zkernel)
	@mkdir -p build/isofiles/boot/grub
	@cp $(zkernel) build/isofiles/boot/kernel.bin
	@cp $(grub_cfg) build/isofiles/boot/grub
	grub-mkrescue -o $(iso) build/isofiles
	@echo OK

zigos: $(iso)

# compile assembly files
build/arch/$(arch)/%.o: arch/$(arch)/%.asm
	@mkdir -p $(shell dirname $@)
	@nasm -felf64 $< -o $@
