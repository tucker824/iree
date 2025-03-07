# Copyright 2019 The IREE Authors
#
# Licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# ***THIS FILE DOES NOT BUILD WITH BAZEL***
#
# It is open sourced to enable Bazel->CMake conversion to maintain test coverage
# of our integration tests in open source while we figure out a long term plan
# for our integration testing.

load(
    "@iree//integrations/tensorflow/e2e:iree_e2e_cartesian_product_test_suite.bzl",
    "iree_e2e_cartesian_product_test_suite",
)

package(
    default_visibility = ["//visibility:public"],
    features = ["layering_check"],
    licenses = ["notice"],  # Apache 2.0
)

[
    py_binary(
        name = src.replace(".py", "_manual"),
        srcs = [src],
        main = src,
        python_version = "PY3",
        deps = [
            "//third_party/py/absl:app",
            "//third_party/py/absl/flags",
            "//third_party/py/iree:pylib_tf_support",
            "//third_party/py/numpy",
            "//third_party/py/tensorflow",
            "//util/debuginfo:signalsafe_addr2line_installer",
        ],
    )
    for src in glob(["*_test.py"])
]

iree_e2e_cartesian_product_test_suite(
    name = "training_tests",
    failing_configurations = [
        {
            "target_backends": "tflite",  # TFLite doesn't support training
        },
        {
            "optimizer": [
                "adadelta",
                "adagrad",
                "adam",
                "adamax",
                "ftrl",
                "nadam",
                "rmsprop",
                "sgd",
            ],
            "target_backends": [
                "iree_llvmaot",
                "iree_vulkan",
            ],
        },
    ],
    matrix = {
        "src": [
            "classification_training_test.py",
            "regression_training_test.py",
        ],
        "reference_backend": "tf",
        "optimizer": [
            "adadelta",
            "adagrad",
            "adam",
            "adamax",
            "ftrl",
            "nadam",
            "rmsprop",
            "sgd",
        ],
        "target_backends": [
            "tf",
            "tflite",
            "iree_llvmaot",
            "iree_vulkan",
        ],
    },
    deps = [
        "//third_party/py/absl:app",
        "//third_party/py/absl/flags",
        "//third_party/py/iree:pylib_tf_support",
        "//third_party/py/numpy",
        "//third_party/py/tensorflow",
        "//util/debuginfo:signalsafe_addr2line_installer",
    ],
)
