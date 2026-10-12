.intel_syntax noprefix
.section .text
.global bind_entry, tick_entry, dispatch_hook, result_hook, exception_hook

# All addresses are module RVAs. The linker resolves RIP-relative references.
# The original native refill, imports, prologue/epilogue and SEH remain in place.
.extern original_entry # 0x1020, resolved by resource_transport.py
.extern original_bind # 0x105d, resolved by resource_transport.py
.extern original_thread_check # 0x139f, resolved by resource_transport.py
.extern original_format # 0x13e1, resolved by resource_transport.py
.extern original_error_format # 0x13f4, resolved by resource_transport.py
.extern original_epilogue # 0x1532, resolved by resource_transport.py
.extern bad_request
.extern native_lock
.extern native_actor
.extern native_error
.extern response_buffer
.extern cached_valid
.extern cached_pawn
.extern cached_pc
.extern cached_world

# A Lua C callback receives only lua_State*. No Lua internals are inspected.
# Tick's caller supplies 15 error strings followed by true. Returning N selects
# the last N existing arguments; Lua's caller keeps the first result. This is
# the standard Lua C-function result convention, without depending on DLL exports
# or the private lua_State layout. Always call Tick with all 16 arguments.
bind_entry:
    xor edx, edx
    jmp original_entry
tick_entry:
    mov edx, 1
    jmp original_entry

# Replaces the conditional jump immediately after the original atomic lock.
# Flags still come from cmpxchg. Per-call mode lives in unused stack padding,
# not shared state. A rejected re-entrant call must never release the lock.
dispatch_hook:
    jne busy
    mov dword ptr [rbp+0x30], edx
    test edx, edx
    jnz fast_dispatch
    mov dword ptr [rip+cached_valid], 0
    jmp original_bind
busy:
    xor eax, eax
    test edx, edx
    jz busy_return
    mov eax, 16
busy_return:
    jmp original_epilogue
fast_dispatch:
    cmp dword ptr [rip+cached_valid], 1
    jne unbound
    mov rax, qword ptr [rip+cached_pawn]
    mov qword ptr [rbp+0x18], rax
    mov rax, qword ptr [rip+cached_pc]
    mov qword ptr [rbp+0x20], rax
    mov rax, qword ptr [rip+cached_world]
    mov qword ptr [rbp+0x28], rax
    mov qword ptr [rip+native_actor], 0
    lea rax, [rip+bad_request]  # BAD_REQUEST until core establishes its own status
    mov qword ptr [rip+native_error], rax
    jmp original_thread_check
unbound:
    mov eax, 15
    jmp unlock_return

# All normal exits from the preserved native core arrive here.
result_hook:
    cmp dword ptr [rbp+0x30], 1
    je fast_result
    mov r9, qword ptr [rip+native_error]
    test r9, r9
    jnz bind_result
    mov rax, qword ptr [rbp+0x18]
    mov qword ptr [rip+cached_pawn], rax
    mov rax, qword ptr [rbp+0x20]
    mov qword ptr [rip+cached_pc], rax
    mov rax, qword ptr [rbp+0x28]
    mov qword ptr [rip+cached_world], rax
    mov dword ptr [rip+cached_valid], 1
bind_result:
    jmp original_format

# The original SEH handler sets NATIVE_EXCEPTION and jumps to error formatting.
# Route tick exceptions through the same no-file error return.
exception_hook:
    cmp dword ptr [rbp+0x30], 1
    je fast_result
    lea rcx, [rip+response_buffer]
    jmp original_error_format

fast_result:
    mov r9, qword ptr [rip+native_error]
    test r9, r9
    jnz failed_result
    mov eax, 1
    jmp unlock_return
failed_result:
    mov dword ptr [rip+cached_valid], 0
    # Each entry is an original error string RVA; no string dereference needed.
    lea r10, [rip+error_rvas]
    lea r11, [rip+bind_entry]
    sub r11, 0x7000  # module base; bind_entry is deliberately first
    mov eax, 13
error_next:
    mov ecx, dword ptr [r10]
    add rcx, r11
    cmp r9, rcx
    je unlock_return
    add r10, 4
    dec eax
    cmp eax, 1
    jne error_next
    mov eax, 14
unlock_return:
    xor edx, edx
    xchg dword ptr [rip+native_lock], edx
    jmp original_epilogue

.balign 4
error_rvas:
    .long 0x3118, 0x3124, 0x3131, 0x31a6, 0x31bd, 0x31ce
    .long 0x31e1, 0x31f9, 0x3207, 0x3218, 0x3229, 0x33c0
