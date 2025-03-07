// Copyright 2020 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Main entry function for iree-tf-opt and derived binaries.
//
// This is a bare-bones, minimal *-opt just for testing the handful of local
// passes here. If you need something, add it, but add only what you need as
// each addition will likely end up on the build critical path.

#include "iree/compiler/Dialect/Flow/IR/FlowDialect.h"
#include "iree/compiler/Dialect/HAL/IR/HALDialect.h"
#include "iree/compiler/Dialect/IREE/IR/IREEDialect.h"
#include "iree/compiler/Dialect/Modules/Strings/IR/Dialect.h"
#include "iree/compiler/Dialect/Modules/TensorList/IR/TensorListOps.h"
#include "iree/tools/init_xla_dialects.h"
#include "iree_tf_compiler/MHLO/Passes.h"
#include "iree_tf_compiler/TF/Passes.h"
#include "iree_tf_compiler/dialect/tf_strings/ir/dialect.h"
#include "iree_tf_compiler/dialect/tf_tensorlist/ir/tf_tensorlist_dialect.h"
#include "llvm/Support/InitLLVM.h"
#include "mlir/IR/Dialect.h"
#include "mlir/Support/MlirOptMain.h"
#include "mlir/Transforms/Passes.h"
#include "tensorflow/compiler/mlir/tensorflow/dialect_registration.h"

int main(int argc, char **argv) {
  llvm::InitLLVM y(argc, argv);

  mlir::DialectRegistry registry;
  mlir::registerXLADialects(registry);
  registry.insert<mlir::iree_compiler::IREE::Flow::FlowDialect,
                  mlir::iree_compiler::IREE::HAL::HALDialect,
                  mlir::iree_compiler::IREEDialect,
                  mlir::iree_compiler::IREE::Strings::StringsDialect,
                  mlir::iree_compiler::IREE::TensorList::TensorListDialect>();
  registry.insert<mlir::iree_integrations::tf_strings::TFStringsDialect>();
  registry
      .insert<mlir::iree_integrations::tf_tensorlist::TFTensorListDialect>();

  mlir::RegisterAllTensorFlowDialects(registry);
  mlir::iree_integrations::TF::registerAllDialects(registry);
  mlir::iree_integrations::TF::registerAllPasses();
  mlir::iree_integrations::MHLO::registerAllPasses();

  // Select MLIR passes.
  mlir::registerCanonicalizerPass();
  mlir::registerCSEPass();
  mlir::registerInlinerPass();

  if (failed(MlirOptMain(argc, argv, "IREE-TF modular optimizer driver\n",
                         registry,
                         /*preloadDialectsInContext=*/false))) {
    return 1;
  }
  return 0;
}
