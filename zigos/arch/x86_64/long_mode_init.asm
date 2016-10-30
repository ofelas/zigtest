; Copyright 2016 Philipp Oppermann. See the README.md
; file at the top-level directory of this distribution.
;
; Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
; http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
; <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
; option. This file may not be copied, modified, or distributed
; except according to those terms.

global long_mode_start
extern zigmain

section .text
bits 64
long_mode_start:
    ; call zig main (with multiboot pointer in rdi)
    ; print "Zig!"
    call zigmain
.os_returned:
    ; zig main returned, print `OS returned!`
    mov rax, 0x4f724f204f534f4f
    mov [0xb80a0], rax
    mov rax, 0x4f724f754f744f65
    mov [0xb80a8], rax
    mov rax, 0x4f214f644f654f6e
    mov [0xb80b0], rax
    hlt
