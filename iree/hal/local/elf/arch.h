// Copyright 2021 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef IREE_HAL_LOCAL_ELF_ARCH_H_
#define IREE_HAL_LOCAL_ELF_ARCH_H_

#include "iree/base/api.h"
#include "iree/hal/local/elf/elf_types.h"

//==============================================================================
// ELF machine type/ABI
//==============================================================================

// Returns true if the reported ELF machine specification is valid.
bool iree_elf_arch_is_valid(const iree_elf_ehdr_t* ehdr);

//==============================================================================
// ELF relocations
//==============================================================================

// State used during relocation.
typedef struct iree_elf_relocation_state_t {
  // Bias applied to all relative addresses (from the string table, etc) in the
  // loaded module. This is an offset from the vaddr_base that may not be 0 if
  // host page granularity was larger than the ELF's defined granularity.
  uint8_t* vaddr_bias;

  // PT_DYNAMIC table.
  iree_host_size_t dyn_table_count;
  const iree_elf_dyn_t* dyn_table;
} iree_elf_relocation_state_t;

// Applies architecture-specific relocations.
iree_status_t iree_elf_arch_apply_relocations(
    iree_elf_relocation_state_t* state);

//==============================================================================
// Cross-ABI function calls
//==============================================================================

// TODO(benvanik): add thunk functions (iree_elf_thunk_*) to be used by imports
// for marshaling from linux ABI in the ELF to host ABI.

// void(*)(void)
void iree_elf_call_v_v(const void* symbol_ptr);

// void*(*)(int)
void* iree_elf_call_p_i(const void* symbol_ptr, int a0);

// void*(*)(int, void*)
void* iree_elf_call_p_ip(const void* symbol_ptr, int a0, void* a1);

// int(*)(void*, void*)
int iree_elf_call_i_pp(const void* symbol_ptr, void* a0, void* a1);

#endif  // IREE_HAL_LOCAL_ELF_ARCH_H_
