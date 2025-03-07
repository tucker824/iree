// Copyright 2020 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef IREE_TOOLS_INIT_COMPILER_MODULES_H_
#define IREE_TOOLS_INIT_COMPILER_MODULES_H_

#include "iree/compiler/Dialect/Modules/Check/IR/CheckDialect.h"
#include "iree/compiler/Dialect/Modules/Strings/IR/Dialect.h"
#include "iree/compiler/Dialect/Modules/TensorList/IR/TensorListDialect.h"

namespace mlir {
namespace iree_compiler {

// Add all the IREE compiler module dialects to the provided registry.
inline void registerIreeCompilerModuleDialects(DialectRegistry &registry) {
  // clang-format off
  registry.insert<IREE::Check::CheckDialect,
                  IREE::Strings::StringsDialect,
                  IREE::TensorList::TensorListDialect>();
  // clang-format on
}

}  // namespace iree_compiler
}  // namespace mlir

#endif  // IREE_TOOLS_INIT_COMPILER_MODULES_H_
