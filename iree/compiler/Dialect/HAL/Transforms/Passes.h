// Copyright 2019 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef IREE_COMPILER_DIALECT_HAL_TRANSFORMS_PASSES_H_
#define IREE_COMPILER_DIALECT_HAL_TRANSFORMS_PASSES_H_

#include "iree/compiler/Dialect/Flow/IR/FlowOps.h"
#include "iree/compiler/Dialect/HAL/IR/HALOps.h"
#include "iree/compiler/Dialect/HAL/Target/TargetBackend.h"
#include "llvm/ADT/StringMap.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/LLVM.h"

namespace mlir {
namespace iree_compiler {
namespace IREE {
namespace HAL {

//===----------------------------------------------------------------------===//
// Helpers
//===----------------------------------------------------------------------===//

// Adds a set of passes to the given pass manager that run the required HAL
// transforms in the canonical order.
//
// Most translation code should prefer to use this instead of manually adding
// the passes themselves to ensure that expected pass ordering is observed.
//
// The expected usage is:
//   <run conversion to flow/sequencer/etc>
//   buildHALTransformPassPipeline & run
//   <run conversion from HAL to vm/etc>
void buildHALTransformPassPipeline(OpPassManager &passManager,
                                   const TargetOptions &targetOptions);

void registerHALTransformPassPipeline();

//===----------------------------------------------------------------------===//
// Conversion
//===----------------------------------------------------------------------===//

// Converts input flow/std/etc dialects to the IREE HAL dialect.
std::unique_ptr<OperationPass<ModuleOp>> createConvertToHALPass();

//===----------------------------------------------------------------------===//
// Device management
//===----------------------------------------------------------------------===//

// Outlines hal.device.switch conditions into functions and inlines conditions.
std::unique_ptr<OperationPass<FuncOp>> createInlineDeviceSwitchesPass();

// Finds hal.device.query ops and creates variables initialized on startup.
std::unique_ptr<OperationPass<ModuleOp>> createMemoizeDeviceQueriesPass();

//===----------------------------------------------------------------------===//
// Executable translation and optimization
//===----------------------------------------------------------------------===//

// Defines hal.executables and hal.interfaces for flow.executable ops based on
// usage within the module. Target backends are queried to check for support and
// device placements are made.
std::unique_ptr<OperationPass<ModuleOp>> createMaterializeInterfacesPass(
    TargetOptions targetOptions);

// Propagates hal.interface.workload.* information when constant.
std::unique_ptr<OperationPass<IREE::HAL::ExecutableTargetOp>>
createPropagateConstantWorkgroupInfoPass();

// Translates hal.executable.target ops via a nested translation pipeline.
std::unique_ptr<OperationPass<IREE::HAL::ExecutableTargetOp>>
createTranslateExecutablesPass(TargetOptions targetOptions);

// Calls into each target backend to have it link multiple hal.executables
// together (if that makes sense). For example, the LLVM AOT backend may combine
// all executable targets for the same architecture into a single executable and
// link it as a shared library.
std::unique_ptr<OperationPass<mlir::ModuleOp>> createLinkExecutablesPass(
    TargetOptions targetOptions);

// Resolves hal.executable.entry_point references to ordinals.
std::unique_ptr<OperationPass<ModuleOp>> createResolveEntryPointOrdinalsPass();

// Converts hal.executable.target ops to hal.executable.binary ops.
std::unique_ptr<OperationPass<IREE::HAL::ExecutableOp>>
createSerializeExecutablesPass(TargetOptions targetOptions);

//===----------------------------------------------------------------------===//
// Resource initialization, caching, and optimization
//===----------------------------------------------------------------------===//

// Combines constant variables into one or more hal.constant_pools based on
// usage semantics.
std::unique_ptr<OperationPass<ModuleOp>> createIdentifyConstantPoolsPass(
    TargetOptions targetOptions);

// Packs all constant data in a hal.constant_pool into their storage formats
// and maps them with hal.constant_pool.span.
std::unique_ptr<OperationPass<ConstantPoolOp>>
createPackConstantPoolStoragePass();

// Materializes runtime buffers for constant pools.
std::unique_ptr<OperationPass<ModuleOp>>
createMaterializeConstantPoolBuffersPass();

// Performs packing and materializes runtime packing code when required.
std::unique_ptr<OperationPass<FuncOp>> createPackAllocationsPass(
    TargetOptions targetOptions);

// Finds all resource lookups (such as hal.executable.lookup), materializes
// their cache storage and initialization, and rewrites the lookups to
// references.
std::unique_ptr<OperationPass<ModuleOp>> createMaterializeResourceCachesPass(
    TargetOptions targetOptions);

// Eliminates redundant 'load's of variables within functions with no 'store'.
// TODO(#1124): replace with memory side effects once supported upstream.
std::unique_ptr<OperationPass<FuncOp>> createCSEVariableLoadsPass();

// Repeats dispatches `iree-hal-repeat-dispatch-num` times, which is 1 by
// default.
std::unique_ptr<OperationPass<FuncOp>> createBenchmarkBatchDispatchesPass(
    unsigned repeatCount);

//===----------------------------------------------------------------------===//
// Register all Passes
//===----------------------------------------------------------------------===//

inline void registerHALPasses() {
  registerHALTransformPassPipeline();
  auto targetOptions = getTargetOptionsFromFlags();
  createConvertToHALPass();
  createBenchmarkBatchDispatchesPass(/*repeatCount=*/1);
  createInlineDeviceSwitchesPass();
  createMemoizeDeviceQueriesPass();
  createTranslateExecutablesPass(targetOptions);
  createLinkExecutablesPass(targetOptions);
  createResolveEntryPointOrdinalsPass();
  createSerializeExecutablesPass(targetOptions);
  createIdentifyConstantPoolsPass(targetOptions);
  createPackConstantPoolStoragePass();
  createMaterializeConstantPoolBuffersPass();
  createPackAllocationsPass(targetOptions);
  createMaterializeResourceCachesPass(targetOptions);
}

}  // namespace HAL
}  // namespace IREE
}  // namespace iree_compiler
}  // namespace mlir

#endif  // IREE_COMPILER_DIALECT_HAL_TRANSFORMS_PASSES_H_
