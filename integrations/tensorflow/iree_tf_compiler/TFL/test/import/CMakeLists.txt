# Copyright 2021 The IREE Authors
#
# Licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

iree_add_all_subdirs()

file(GLOB _GLOB_X_MLIR LIST_DIRECTORIES false RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS *.mlir)
file(GLOB _GLOB_X_TFLITE LIST_DIRECTORIES false RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS *.tflite)
iree_lit_test_suite(
  NAME
    lit
  SRCS
    "${_GLOB_X_MLIR}"
  DATA
    "${_GLOB_X_TFLITE}"
    iree::tools::IreeFileCheck
    iree_tf_compiler_iree-import-tflite
)
