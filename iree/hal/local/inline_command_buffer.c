// Copyright 2021 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "iree/hal/local/inline_command_buffer.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "iree/base/api.h"
#include "iree/base/internal/math.h"
#include "iree/base/tracing.h"
#include "iree/hal/local/executable_library.h"
#include "iree/hal/local/local_descriptor_set_layout.h"
#include "iree/hal/local/local_executable.h"
#include "iree/hal/local/local_executable_layout.h"

//===----------------------------------------------------------------------===//
// iree_hal_inline_command_buffer_t
//===----------------------------------------------------------------------===//

// Inline synchronous one-shot command "buffer".
typedef struct iree_hal_inline_command_buffer_t {
  iree_hal_resource_t resource;

  iree_hal_device_t* device;
  iree_hal_command_buffer_mode_t mode;
  iree_hal_command_category_t allowed_categories;
  iree_hal_queue_affinity_t queue_affinity;

  struct {
    // A flattened list of all available descriptor set bindings.
    // As descriptor sets are pushed/bound the bindings will be updated to
    // represent the fully-translated binding data pointer.
    //
    // TODO(benvanik): support proper mapping semantics and track the
    // iree_hal_buffer_mapping_t and map/unmap where appropriate.
    void* full_bindings[IREE_HAL_LOCAL_MAX_DESCRIPTOR_SET_COUNT *
                        IREE_HAL_LOCAL_MAX_DESCRIPTOR_BINDING_COUNT];
    size_t full_binding_lengths[IREE_HAL_LOCAL_MAX_DESCRIPTOR_SET_COUNT *
                                IREE_HAL_LOCAL_MAX_DESCRIPTOR_BINDING_COUNT];

    // Packed bindings scratch space used during dispatch. Executable bindings
    // are packed into a dense list with unused bindings removed.
    void* packed_bindings[IREE_HAL_LOCAL_MAX_DESCRIPTOR_SET_COUNT *
                          IREE_HAL_LOCAL_MAX_DESCRIPTOR_BINDING_COUNT];
    size_t packed_binding_lengths[IREE_HAL_LOCAL_MAX_DESCRIPTOR_SET_COUNT *
                                  IREE_HAL_LOCAL_MAX_DESCRIPTOR_BINDING_COUNT];

    // All available push constants updated each time push_constants is called.
    // Reset only with the command buffer and otherwise will maintain its values
    // during recording to allow for partial push_constants updates.
    uint32_t push_constants[IREE_HAL_LOCAL_MAX_PUSH_CONSTANT_COUNT];

    // Cached and initialized dispatch state reused for all dispatches.
    // Individual dispatches must populate the dynamically changing fields like
    // push_constant_count and binding_count.
    iree_hal_executable_dispatch_state_v0_t dispatch_state;
  } state;
} iree_hal_inline_command_buffer_t;

static const iree_hal_command_buffer_vtable_t
    iree_hal_inline_command_buffer_vtable;

static iree_hal_inline_command_buffer_t* iree_hal_inline_command_buffer_cast(
    iree_hal_command_buffer_t* base_value) {
  IREE_HAL_ASSERT_TYPE(base_value, &iree_hal_inline_command_buffer_vtable);
  return (iree_hal_inline_command_buffer_t*)base_value;
}

static void iree_hal_inline_command_buffer_reset(
    iree_hal_inline_command_buffer_t* command_buffer) {
  memset(&command_buffer->state, 0, sizeof(command_buffer->state));

  // Setup the cached dispatch state pointers that don't change.
  iree_hal_executable_dispatch_state_v0_t* dispatch_state =
      &command_buffer->state.dispatch_state;
  dispatch_state->push_constants = command_buffer->state.push_constants;
  dispatch_state->binding_ptrs = command_buffer->state.packed_bindings;
  dispatch_state->binding_lengths =
      command_buffer->state.packed_binding_lengths;
}

iree_status_t iree_hal_inline_command_buffer_create(
    iree_hal_device_t* device, iree_hal_command_buffer_mode_t mode,
    iree_hal_command_category_t command_categories,
    iree_hal_queue_affinity_t queue_affinity,
    iree_hal_command_buffer_t** out_command_buffer) {
  IREE_ASSERT_ARGUMENT(device);
  IREE_ASSERT_ARGUMENT(out_command_buffer);
  *out_command_buffer = NULL;
  if (!iree_all_bits_set(
          mode, IREE_HAL_COMMAND_BUFFER_MODE_ONE_SHOT |
                    IREE_HAL_COMMAND_BUFFER_MODE_ALLOW_INLINE_EXECUTION)) {
    // This implementation only supports command buffers that are allowed to
    // execute inline. This mode is a contract with the caller that it is ok if
    // we begin executing prior to submission.
    return iree_make_status(
        IREE_STATUS_INVALID_ARGUMENT,
        "inline command buffers must have a mode with ALLOW_INLINE_EXECUTION");
  }

  IREE_TRACE_ZONE_BEGIN(z0);

  iree_hal_inline_command_buffer_t* command_buffer = NULL;
  iree_status_t status =
      iree_allocator_malloc(iree_hal_device_host_allocator(device),
                            sizeof(*command_buffer), (void**)&command_buffer);
  if (iree_status_is_ok(status)) {
    iree_hal_resource_initialize(&iree_hal_inline_command_buffer_vtable,
                                 &command_buffer->resource);
    command_buffer->device = device;
    command_buffer->mode = mode;
    command_buffer->allowed_categories = command_categories;
    command_buffer->queue_affinity = queue_affinity;
    iree_hal_inline_command_buffer_reset(command_buffer);

    *out_command_buffer = (iree_hal_command_buffer_t*)command_buffer;
  }

  IREE_TRACE_ZONE_END(z0);
  return status;
}

static void iree_hal_inline_command_buffer_destroy(
    iree_hal_command_buffer_t* base_command_buffer) {
  iree_hal_inline_command_buffer_t* command_buffer =
      iree_hal_inline_command_buffer_cast(base_command_buffer);
  iree_allocator_t host_allocator =
      iree_hal_device_host_allocator(command_buffer->device);
  IREE_TRACE_ZONE_BEGIN(z0);

  iree_hal_inline_command_buffer_reset(command_buffer);
  iree_allocator_free(host_allocator, command_buffer);

  IREE_TRACE_ZONE_END(z0);
}

static iree_hal_command_buffer_mode_t iree_hal_inline_command_buffer_mode(
    const iree_hal_command_buffer_t* base_command_buffer) {
  return ((const iree_hal_inline_command_buffer_t*)base_command_buffer)->mode;
}

static iree_hal_command_category_t
iree_hal_inline_command_buffer_allowed_categories(
    const iree_hal_command_buffer_t* base_command_buffer) {
  return ((const iree_hal_inline_command_buffer_t*)base_command_buffer)
      ->allowed_categories;
}

//===----------------------------------------------------------------------===//
// iree_hal_inline_command_buffer_t recording
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_flush_tasks(
    iree_hal_inline_command_buffer_t* command_buffer);

static iree_status_t iree_hal_inline_command_buffer_begin(
    iree_hal_command_buffer_t* base_command_buffer) {
  iree_hal_inline_command_buffer_t* command_buffer =
      iree_hal_inline_command_buffer_cast(base_command_buffer);
  iree_hal_inline_command_buffer_reset(command_buffer);
  return iree_ok_status();
}

static iree_status_t iree_hal_inline_command_buffer_end(
    iree_hal_command_buffer_t* base_command_buffer) {
  iree_hal_inline_command_buffer_t* command_buffer =
      iree_hal_inline_command_buffer_cast(base_command_buffer);
  iree_hal_inline_command_buffer_reset(command_buffer);
  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_execution_barrier
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_execution_barrier(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_execution_stage_t source_stage_mask,
    iree_hal_execution_stage_t target_stage_mask,
    iree_hal_execution_barrier_flags_t flags,
    iree_host_size_t memory_barrier_count,
    const iree_hal_memory_barrier_t* memory_barriers,
    iree_host_size_t buffer_barrier_count,
    const iree_hal_buffer_barrier_t* buffer_barriers) {
  // No-op; we execute synchronously.
  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_signal_event
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_signal_event(
    iree_hal_command_buffer_t* base_command_buffer, iree_hal_event_t* event,
    iree_hal_execution_stage_t source_stage_mask) {
  // No-op; we execute synchronously.
  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_reset_event
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_reset_event(
    iree_hal_command_buffer_t* base_command_buffer, iree_hal_event_t* event,
    iree_hal_execution_stage_t source_stage_mask) {
  // No-op; we execute synchronously.
  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_wait_events
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_wait_events(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_host_size_t event_count, const iree_hal_event_t** events,
    iree_hal_execution_stage_t source_stage_mask,
    iree_hal_execution_stage_t target_stage_mask,
    iree_host_size_t memory_barrier_count,
    const iree_hal_memory_barrier_t* memory_barriers,
    iree_host_size_t buffer_barrier_count,
    const iree_hal_buffer_barrier_t* buffer_barriers) {
  // No-op; we execute synchronously.
  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_discard_buffer
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_discard_buffer(
    iree_hal_command_buffer_t* base_command_buffer, iree_hal_buffer_t* buffer) {
  // Could be treated as a cache invalidation as it indicates we won't be using
  // the existing buffer contents again.
  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_fill_buffer
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_fill_buffer(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_buffer_t* target_buffer, iree_device_size_t target_offset,
    iree_device_size_t length, const void* pattern,
    iree_host_size_t pattern_length) {
  return iree_hal_buffer_fill(target_buffer, target_offset, length, pattern,
                              pattern_length);
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_update_buffer
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_update_buffer(
    iree_hal_command_buffer_t* base_command_buffer, const void* source_buffer,
    iree_host_size_t source_offset, iree_hal_buffer_t* target_buffer,
    iree_device_size_t target_offset, iree_device_size_t length) {
  return iree_hal_buffer_write_data(
      target_buffer, target_offset,
      (const uint8_t*)source_buffer + source_offset, length);
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_copy_buffer
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_copy_buffer(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_buffer_t* source_buffer, iree_device_size_t source_offset,
    iree_hal_buffer_t* target_buffer, iree_device_size_t target_offset,
    iree_device_size_t length) {
  return iree_hal_buffer_copy_data(source_buffer, source_offset, target_buffer,
                                   target_offset, length);
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_push_constants
//===----------------------------------------------------------------------===//
// NOTE: command buffer state change only; enqueues no tasks.

static iree_status_t iree_hal_inline_command_buffer_push_constants(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_executable_layout_t* executable_layout, iree_host_size_t offset,
    const void* values, iree_host_size_t values_length) {
  iree_hal_inline_command_buffer_t* command_buffer =
      iree_hal_inline_command_buffer_cast(base_command_buffer);

  if (IREE_UNLIKELY(offset + values_length >=
                    sizeof(command_buffer->state.push_constants))) {
    return iree_make_status(IREE_STATUS_INVALID_ARGUMENT,
                            "push constant range %zu (length=%zu) out of range",
                            offset, values_length);
  }

  memcpy((uint8_t*)&command_buffer->state.push_constants + offset, values,
         values_length);

  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_push_descriptor_set
//===----------------------------------------------------------------------===//
// NOTE: command buffer state change only; enqueues no tasks.

static iree_status_t iree_hal_inline_command_buffer_push_descriptor_set(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_executable_layout_t* executable_layout, uint32_t set,
    iree_host_size_t binding_count,
    const iree_hal_descriptor_set_binding_t* bindings) {
  iree_hal_inline_command_buffer_t* command_buffer =
      iree_hal_inline_command_buffer_cast(base_command_buffer);

  if (IREE_UNLIKELY(set >= IREE_HAL_LOCAL_MAX_DESCRIPTOR_SET_COUNT)) {
    return iree_make_status(IREE_STATUS_INVALID_ARGUMENT,
                            "set %u out of bounds", set);
  }

  iree_hal_local_executable_layout_t* local_executable_layout =
      iree_hal_local_executable_layout_cast(executable_layout);
  iree_hal_local_descriptor_set_layout_t* local_set_layout =
      iree_hal_local_descriptor_set_layout_cast(
          local_executable_layout->set_layouts[set]);

  iree_host_size_t binding_base =
      set * IREE_HAL_LOCAL_MAX_DESCRIPTOR_BINDING_COUNT;
  for (iree_host_size_t i = 0; i < binding_count; ++i) {
    if (IREE_UNLIKELY(bindings[i].binding >=
                      IREE_HAL_LOCAL_MAX_DESCRIPTOR_BINDING_COUNT)) {
      return iree_make_status(IREE_STATUS_INVALID_ARGUMENT,
                              "buffer binding index out of bounds");
    }
    iree_host_size_t binding_ordinal = binding_base + bindings[i].binding;

    // TODO(benvanik): track mapping so we can properly map/unmap/flush/etc.
    iree_hal_buffer_mapping_t buffer_mapping;
    IREE_RETURN_IF_ERROR(iree_hal_buffer_map_range(
        bindings[i].buffer, local_set_layout->bindings[binding_ordinal].access,
        bindings[i].offset, bindings[i].length, &buffer_mapping));
    command_buffer->state.full_bindings[binding_ordinal] =
        buffer_mapping.contents.data;
    command_buffer->state.full_binding_lengths[binding_ordinal] =
        buffer_mapping.contents.data_length;
  }

  return iree_ok_status();
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_bind_descriptor_set
//===----------------------------------------------------------------------===//
// NOTE: command buffer state change only; enqueues no tasks.

static iree_status_t iree_hal_inline_command_buffer_bind_descriptor_set(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_executable_layout_t* executable_layout, uint32_t set,
    iree_hal_descriptor_set_t* descriptor_set,
    iree_host_size_t dynamic_offset_count,
    const iree_device_size_t* dynamic_offsets) {
  return iree_make_status(IREE_STATUS_UNIMPLEMENTED,
                          "descriptor set binding not yet implemented");
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_dispatch
//===----------------------------------------------------------------------===//

static iree_status_t iree_hal_inline_command_buffer_dispatch(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_executable_t* executable, int32_t entry_point,
    uint32_t workgroup_x, uint32_t workgroup_y, uint32_t workgroup_z) {
  iree_hal_inline_command_buffer_t* command_buffer =
      iree_hal_inline_command_buffer_cast(base_command_buffer);

  iree_hal_local_executable_t* local_executable =
      iree_hal_local_executable_cast(executable);
  iree_hal_local_executable_layout_t* local_layout =
      local_executable->executable_layouts[entry_point];

  iree_hal_executable_dispatch_state_v0_t* dispatch_state =
      &command_buffer->state.dispatch_state;

  // TODO(benvanik): pull imports from layout.
  dispatch_state->imports = NULL;

  // TODO(benvanik): expose on API or keep fixed on executable.
  dispatch_state->workgroup_size.x = 1;
  dispatch_state->workgroup_size.y = 1;
  dispatch_state->workgroup_size.z = 1;
  dispatch_state->workgroup_count.x = workgroup_x;
  dispatch_state->workgroup_count.y = workgroup_y;
  dispatch_state->workgroup_count.z = workgroup_z;

  // Push constants are pulled directly from the command buffer state, but we
  // only allow the dispatch to read what we know is initialized based on the
  // layout.
  dispatch_state->push_constant_count = local_layout->push_constants;

  // Produce the dense binding list based on the declared bindings used.
  // This allows us to change the descriptor sets and bindings counts supported
  // in the HAL independent of any executable as each executable just gets the
  // flat dense list and doesn't care about our descriptor set stuff.
  //
  // Note that we are just directly setting the binding data pointers here with
  // no ownership/retaining/etc - it's part of the HAL contract that buffers are
  // kept valid for the duration they may be in use.
  iree_hal_local_binding_mask_t used_binding_mask = local_layout->used_bindings;
  iree_host_size_t used_binding_count =
      iree_math_count_ones_u64(used_binding_mask);
  dispatch_state->binding_count = used_binding_count;
  void** binding_ptrs = (void**)dispatch_state->binding_ptrs;
  size_t* binding_lengths = (size_t*)dispatch_state->binding_lengths;
  iree_host_size_t binding_base = 0;
  for (iree_host_size_t i = 0; i < used_binding_count; ++i) {
    int mask_offset = iree_math_count_trailing_zeros_u64(used_binding_mask);
    int binding_ordinal = binding_base + mask_offset;
    binding_base += mask_offset + 1;
    used_binding_mask = iree_shr(used_binding_mask, mask_offset + 1);
    binding_ptrs[i] = command_buffer->state.full_bindings[binding_ordinal];
    if (!binding_ptrs[i]) {
      return iree_make_status(IREE_STATUS_FAILED_PRECONDITION,
                              "(flat) binding %d is NULL", binding_ordinal);
    }
    binding_lengths[i] =
        command_buffer->state.full_binding_lengths[binding_ordinal];
  }

  return iree_hal_local_executable_issue_dispatch_inline(
      local_executable, entry_point, dispatch_state);
}

static iree_status_t iree_hal_inline_command_buffer_dispatch_indirect(
    iree_hal_command_buffer_t* base_command_buffer,
    iree_hal_executable_t* executable, int32_t entry_point,
    iree_hal_buffer_t* workgroups_buffer,
    iree_device_size_t workgroups_offset) {
  // TODO(benvanik): track mapping so we can properly map/unmap/flush/etc.
  iree_hal_buffer_mapping_t buffer_mapping;
  IREE_RETURN_IF_ERROR(iree_hal_buffer_map_range(
      workgroups_buffer, IREE_HAL_MEMORY_ACCESS_READ, workgroups_offset,
      3 * sizeof(uint32_t), &buffer_mapping));
  iree_hal_vec3_t workgroup_count =
      *(const iree_hal_vec3_t*)buffer_mapping.contents.data;
  return iree_hal_inline_command_buffer_dispatch(
      base_command_buffer, executable, entry_point, workgroup_count.x,
      workgroup_count.y, workgroup_count.z);
}

//===----------------------------------------------------------------------===//
// iree_hal_command_buffer_vtable_t
//===----------------------------------------------------------------------===//

static const iree_hal_command_buffer_vtable_t
    iree_hal_inline_command_buffer_vtable = {
        .destroy = iree_hal_inline_command_buffer_destroy,
        .mode = iree_hal_inline_command_buffer_mode,
        .allowed_categories = iree_hal_inline_command_buffer_allowed_categories,
        .begin = iree_hal_inline_command_buffer_begin,
        .end = iree_hal_inline_command_buffer_end,
        .execution_barrier = iree_hal_inline_command_buffer_execution_barrier,
        .signal_event = iree_hal_inline_command_buffer_signal_event,
        .reset_event = iree_hal_inline_command_buffer_reset_event,
        .wait_events = iree_hal_inline_command_buffer_wait_events,
        .discard_buffer = iree_hal_inline_command_buffer_discard_buffer,
        .fill_buffer = iree_hal_inline_command_buffer_fill_buffer,
        .update_buffer = iree_hal_inline_command_buffer_update_buffer,
        .copy_buffer = iree_hal_inline_command_buffer_copy_buffer,
        .push_constants = iree_hal_inline_command_buffer_push_constants,
        .push_descriptor_set =
            iree_hal_inline_command_buffer_push_descriptor_set,
        .bind_descriptor_set =
            iree_hal_inline_command_buffer_bind_descriptor_set,
        .dispatch = iree_hal_inline_command_buffer_dispatch,
        .dispatch_indirect = iree_hal_inline_command_buffer_dispatch_indirect,
};
