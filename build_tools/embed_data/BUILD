# Copyright 2019 The IREE Authors
#
# Licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Generates source files with embedded file contents.

load(":build_defs.bzl", "c_embed_data")

package(
    default_visibility = ["//visibility:public"],
    features = ["layering_check"],
    licenses = ["notice"],  # Apache 2.0
)

cc_binary(
    name = "generate_embed_data",
    srcs = ["generate_embed_data_main.cc"],
    deps = [
        "@com_google_absl//absl/flags:flag",
        "@com_google_absl//absl/flags:parse",
        "@com_google_absl//absl/strings",
    ],
)

c_embed_data(
    name = "testembed1",
    # do not sort
    srcs = [
        "file1.bin",
        "data/file2.bin",
    ],
    c_file_output = "testembed1.c",
    flatten = True,
    h_file_output = "testembed1.h",
)

c_embed_data(
    name = "testembed2",
    srcs = [
        "data/file3.bin",
    ],
    c_file_output = "testembed2.c",
    flatten = True,
    h_file_output = "testembed2.h",
)

cc_test(
    name = "c_embed_data_test",
    srcs = ["c_embed_data_test.cc"],
    deps = [
        ":testembed1",
        ":testembed2",
        "//iree/testing:gtest",
        "//iree/testing:gtest_main",
    ],
)
