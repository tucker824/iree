// RUN: iree-opt -split-input-file -iree-codegen-hlo-to-linalg-on-tensors %s | IreeFileCheck %s

// Check the non-broadcast case for each registered op, then just check a
// representative op for detailed broadcast semantics. Since the broadcasting
// implementation lowers through hlo ops, we are primarily checking broadcast
// semantics and not exhaustively checking that the non broadcasting ops lower
// to the right linalg sequences.

// CHECK-LABEL: @addWithoutBroadcast
func @addWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK: linalg.generic
  // CHECK-SAME: outs(%0 : tensor<4xf32>
  // CHECK: addf
  // CHECK-NOT: linalg.generic
  %0 = chlo.broadcast_add %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK: #map0 = affine_map<(d0, d1) -> (d1)>
// CHECK: #map1 = affine_map<(d0, d1) -> (d0, d1)>
// CHECK-LABEL: @dynamicBroadcast
func @dynamicBroadcast(%arg0: tensor<?xf32>, %arg1: tensor<?x?xf32>) -> tensor<?x?xf32> {
  // Should broadcast %arg0 -> %arg1 and assert on dynamic expansion.

  // CHECK: %[[C0_0:.*]] = constant 0 : index
  // CHECK: %[[ARG0_D0:.*]] = memref.dim %arg0, %[[C0_0]]
  // CHECK: %[[C0_1:.*]] = constant 0 : index
  // CHECK: %[[ARG1_D0:.*]] = memref.dim %arg1, %[[C0_1]] : tensor<?x?xf32>
  // CHECK: %[[C1_0:.*]] = constant 1 : index
  // CHECK: %[[ARG1_D1:.*]] = memref.dim %arg1, %[[C1_0]] : tensor<?x?xf32>
  // CHECK: %[[EQ:.*]] = cmpi eq, %[[ARG0_D0]], %[[ARG1_D1]] : index
  // CHECK: assert %[[EQ]], "mismatched dynamic broadcast extents"

  // CHECK: %[[INIT_0:.*]] = linalg.init_tensor [%[[ARG1_D0]], %[[ARG0_D0]]] : tensor<?x?xf32>
  // CHECK: %[[BCAST_ARG0:.*]] = linalg.generic {indexing_maps = [#map0, #map1], iterator_types = ["parallel", "parallel"]}
  // CHECK-SAME: ins(%arg0 : tensor<?xf32>) outs(%[[INIT_0]] : tensor<?x?xf32>)

  // CHECK: %[[RESULT:.*]] = linalg.generic
  // CHECK-SAME: ins(%[[BCAST_ARG0]], %arg1 : tensor<?x?xf32>, tensor<?x?xf32>)

  // CHECK-NOT: mhlo.add
  %0 = chlo.broadcast_add %arg0, %arg1 : (tensor<?xf32>, tensor<?x?xf32>) -> tensor<?x?xf32>
  return %0 : tensor<?x?xf32>
}

// -----
// Verifies that broadcast_dimensions validity checks are valid.
// CHECK-LABEL: @dynamicNonScalarBroadcastDimensions
func @dynamicNonScalarBroadcastDimensions(%arg0: tensor<1x4xf32>, %arg1: tensor<4xf32>) -> tensor<1x4xf32> {
  %0 = chlo.broadcast_add %arg0, %arg1 {broadcast_dimensions = dense<1> : tensor<1xi64>} : (tensor<1x4xf32>, tensor<4xf32>) -> tensor<1x4xf32>
  return %0 : tensor<1x4xf32>
}

// -----
// Verifies that broadcast_dimensions validity checks are valid.
// CHECK-LABEL: @dynamicNonScalarByScalarBroadcastDimensions
func @dynamicNonScalarByScalarBroadcastDimensions(%arg0: tensor<1x4xf32>, %arg1: tensor<f32>) -> tensor<1x4xf32> {
  %0 = chlo.broadcast_add %arg0, %arg1 {broadcast_dimensions = dense<[]> : tensor<0xi64>} : (tensor<1x4xf32>, tensor<f32>) -> tensor<1x4xf32>
  return %0 : tensor<1x4xf32>
}

// -----
// CHECK-LABEL: @dynamicBroadcastComplex
func @dynamicBroadcastComplex(%arg0: tensor<?xf32>, %arg1: tensor<?x?xf32>) -> (tensor<?x?xf32>, tensor<?x?xf32>) {
  // CHECK-NOT: mhlo.complex
  // CHECK-NOT: chlo.broadcast_complex
  %0 = chlo.broadcast_complex %arg0, %arg1 : (tensor<?xf32>, tensor<?x?xf32>) -> tensor<?x?xcomplex<f32>>

  %1 = "mhlo.real"(%0) : (tensor<?x?xcomplex<f32>>) -> tensor<?x?xf32>
  %2 = "mhlo.imag"(%0) : (tensor<?x?xcomplex<f32>>) -> tensor<?x?xf32>

  return %1, %2 : tensor<?x?xf32>, tensor<?x?xf32>
}

// -----
// CHECK-LABEL: @dynamicBroadcastCompare
func @dynamicBroadcastCompare(%arg0: tensor<?xf32>, %arg1: tensor<?x?xf32>) -> tensor<?x?xi1> {
  // NOTE: compare is unique because of the element type switch. The pattern
  // will fail or the verifier will catch it if wrong.
  // CHECK-NOT: mhlo.compare
  %0 = chlo.broadcast_compare %arg0, %arg1 {comparison_direction = "EQ"} : (tensor<?xf32>, tensor<?x?xf32>) -> tensor<?x?xi1>
  return %0 : tensor<?x?xi1>
}

// -----
// CHECK-LABEL: func @selectv2
func @selectv2(%arg0: tensor<2xi1>, %arg1: tensor<2xi32>, %arg2: tensor<2xi32>) -> tensor<2xi32> {
  // All same type: should just short-circtuit to one mhlo.select / one generic.
  // CHECK: linalg.generic
  // CHECK:   %[[BODY:.*]] = select
  // CHECK-NOT: linalg.generic
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<2xi1>, tensor<2xi32>, tensor<2xi32>) -> tensor<2xi32>
  return %0: tensor<2xi32>
}

// -----
// CHECK: #map0 = affine_map<(d0) -> ()>
// CHECK: #map1 = affine_map<(d0) -> (d0)>
// CHECK-LABEL: func @selectv2_pred_scalar
func @selectv2_pred_scalar(%arg0: tensor<i1>, %arg1: tensor<2xi32>, %arg2: tensor<2xi32>) -> tensor<2xi32> {
  // CHECK: %[[INIT_0:.*]] = linalg.init_tensor [2] : tensor<2xi1>
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic {indexing_maps = [#map0, #map1], iterator_types = ["parallel"]} ins(%arg0 : tensor<i1>) outs(%[[INIT_0]] : tensor<2xi1>)
  // CHECK: %[[INIT_1:.*]] = linalg.init_tensor [2] : tensor<2xi32>
  // CHECK: linalg.generic
  // CHECK-SAME: ins(%[[BCAST_PRED]], %arg1, %arg2 : tensor<2xi1>, tensor<2xi32>, tensor<2xi32>) outs(%[[INIT_1]] : tensor<2xi32>)
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<i1>, tensor<2xi32>, tensor<2xi32>) -> tensor<2xi32>
  return %0: tensor<2xi32>
}

// -----
// CHECK: #map0 = affine_map<(d0, d1, d2) -> ()>
// CHECK: #map1 = affine_map<(d0, d1, d2) -> (d0, d1, d2)>
// CHECK: #map2 = affine_map<(d0, d1, d2) -> (d1, 0)>
// CHECK-LABEL: func @selectv2_broadcast_then
func @selectv2_broadcast_then(%arg0: tensor<i1>, %arg1: tensor<8x1xi32>, %arg2: tensor<2x8x8xi32>) -> tensor<2x8x8xi32> {
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic {indexing_maps = [#map0, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg0 : tensor<i1>)
  // CHECK: %[[BCAST_THEN:.*]] = linalg.generic {indexing_maps = [#map2, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg1 : tensor<8x1xi32>)
  // CHECK: linalg.generic
  // CHECK-SAME: ins(%[[BCAST_PRED]], %[[BCAST_THEN]], %arg2 : tensor<2x8x8xi1>, tensor<2x8x8xi32>, tensor<2x8x8xi32>)
  // CHECK: select
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<i1>, tensor<8x1xi32>, tensor<2x8x8xi32>) -> tensor<2x8x8xi32>
  return %0: tensor<2x8x8xi32>
}

// -----
// CHECK: #map0 = affine_map<(d0, d1, d2) -> ()>
// CHECK: #map1 = affine_map<(d0, d1, d2) -> (d0, d1, d2)>
// CHECK: #map2 = affine_map<(d0, d1, d2) -> (d1, 0)>
// CHECK-LABEL: func @selectv2_broadcast_else
func @selectv2_broadcast_else(%arg0: tensor<i1>, %arg1: tensor<2x8x8xi32>, %arg2: tensor<8x1xi32>) -> tensor<2x8x8xi32> {
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic {indexing_maps = [#map0, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg0 : tensor<i1>)
  // CHECK: %[[BCAST_ELSE:.*]] = linalg.generic {indexing_maps = [#map2, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg2 : tensor<8x1xi32>)
  // CHECK: linalg.generic
  // CHECK-SAME: ins(%[[BCAST_PRED]], %arg1, %[[BCAST_ELSE]] : tensor<2x8x8xi1>, tensor<2x8x8xi32>, tensor<2x8x8xi32>)
  // CHECK: select
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<i1>, tensor<2x8x8xi32>, tensor<8x1xi32>) -> tensor<2x8x8xi32>
  return %0: tensor<2x8x8xi32>
}

// -----
// CHECK: #map0 = affine_map<(d0, d1, d2) -> (0)>
// CHECK: #map1 = affine_map<(d0, d1, d2) -> (d0, d1, d2)>
// CHECK-LABEL: func @selectv2_broadcast_pred
func @selectv2_broadcast_pred(%arg0: tensor<1xi1>, %arg1: tensor<2x8x8xi32>, %arg2: tensor<2x8x8xi32>) -> tensor<2x8x8xi32> {
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic {indexing_maps = [#map0, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg0 : tensor<1xi1>)
  // CHECK: linalg.generic
  // CHECK-SAME: ins(%[[BCAST_PRED]], %arg1, %arg2 : tensor<2x8x8xi1>, tensor<2x8x8xi32>, tensor<2x8x8xi32>)
  // CHECK: select
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<1xi1>, tensor<2x8x8xi32>, tensor<2x8x8xi32>) -> tensor<2x8x8xi32>
  return %0: tensor<2x8x8xi32>
}

// -----
// CHECK: #map0 = affine_map<(d0, d1, d2) -> (d0, 0, 0)>
// CHECK: #map1 = affine_map<(d0, d1, d2) -> (d0, d1, d2)>
// CHECK: #map2 = affine_map<(d0, d1, d2) -> (0, d1, 0)>
// CHECK: #map3 = affine_map<(d0, d1, d2) -> (0, 0, d2)>
// CHECK-LABEL: func @selectv2_broadcast_all
func @selectv2_broadcast_all(%arg0: tensor<8x1x1xi1>, %arg1: tensor<1x8x1xi32>, %arg2: tensor<1x1x8xi32>) -> tensor<8x8x8xi32> {
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic {indexing_maps = [#map0, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg0 : tensor<8x1x1xi1>)
  // CHECK: %[[BCAST_THEN:.*]] = linalg.generic {indexing_maps = [#map2, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg1 : tensor<1x8x1xi32>)
  // CHECK: %[[BCAST_ELSE:.*]] = linalg.generic {indexing_maps = [#map3, #map1], iterator_types = ["parallel", "parallel", "parallel"]} ins(%arg2 : tensor<1x1x8xi32>)
  // CHECK: linalg.generic
  // CHECK-SAME: ins(%[[BCAST_PRED]], %[[BCAST_THEN]], %[[BCAST_ELSE]] : tensor<8x8x8xi1>, tensor<8x8x8xi32>, tensor<8x8x8xi32>)
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<8x1x1xi1>, tensor<1x8x1xi32>, tensor<1x1x8xi32>) -> tensor<8x8x8xi32>
  return %0: tensor<8x8x8xi32>
}

// -----
// CHECK: #map0 = affine_map<(d0, d1, d2) -> (d0, 0, 0)>
// CHECK: #map1 = affine_map<(d0, d1, d2) -> (d0, d1, d2)>
// CHECK: #map2 = affine_map<(d0, d1, d2) -> (0, d1, 0)>
// CHECK: #map3 = affine_map<(d0, d1, d2) -> (0, 0, d2)>
// CHECK-LABEL: func @selectv2_broadcast_dyn_pred
func @selectv2_broadcast_dyn_pred(%arg0: tensor<?x1x1xi1>, %arg1: tensor<1x8x1xi32>, %arg2: tensor<1x1x8xi32>) -> tensor<?x8x8xi32> {
  // CHECK: %[[C0_0:.*]] = constant 0 : index
  // CHECK: %[[DIM_PRED_0:.*]] = memref.dim %arg0, %[[C0_0]]
  // CHECK: %[[INIT_PRED:.*]] = linalg.init_tensor [%[[DIM_PRED_0]], 8, 8]
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map0, #map1]
  //     CHECK-SAME: ins(%arg0 : tensor<?x1x1xi1>) outs(%[[INIT_PRED]] : tensor<?x8x8xi1>)
  // CHECK: %[[INIT_THEN:.*]] = linalg.init_tensor [%[[DIM_PRED_0]], 8, 8]
  // CHECK: %[[BCAST_THEN:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map2, #map1]
  //     CHECK-SAME: ins(%arg1 : tensor<1x8x1xi32>) outs(%[[INIT_THEN]] : tensor<?x8x8xi32>)
  // CHECK: %[[INIT_ELSE:.*]] = linalg.init_tensor [%[[DIM_PRED_0]], 8, 8]
  // CHECK: %[[BCAST_ELSE:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map3, #map1]
  //     CHECK-SAME: ins(%arg2 : tensor<1x1x8xi32>) outs(%[[INIT_ELSE]] : tensor<?x8x8xi32>)
  // CHECK: %[[C0_1:.*]] = constant 0 : index
  // CHECK: %[[DIM_BCAST_PRED_0:.*]] = memref.dim %[[BCAST_PRED]], %[[C0_1]]
  // CHECK: %[[INIT_RESULT:.*]] = linalg.init_tensor [%[[DIM_BCAST_PRED_0]], 8, 8]
  // CHECK: linalg.generic
  //     CHECK-SAME: ins(%[[BCAST_PRED]], %[[BCAST_THEN]], %[[BCAST_ELSE]] : tensor<?x8x8xi1>, tensor<?x8x8xi32>, tensor<?x8x8xi32>) outs(%[[INIT_RESULT]] : tensor<?x8x8xi32>)
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<?x1x1xi1>, tensor<1x8x1xi32>, tensor<1x1x8xi32>) -> tensor<?x8x8xi32>
  return %0: tensor<?x8x8xi32>
}

// -----
// CHECK-LABEL: func @selectv2_broadcast_dyn_then
func @selectv2_broadcast_dyn_then(%arg0: tensor<8x1x1xi1>, %arg1: tensor<1x?x1xi32>, %arg2: tensor<1x1x8xi32>) -> tensor<8x?x8xi32> {
  // CHECK: %[[C1_0:.*]] = constant 1 : index
  // CHECK: %[[DIM_THEN_1:.*]] = memref.dim %arg1, %[[C1_0]]
  // CHECK: %[[INIT_PRED:.*]] = linalg.init_tensor [8, %[[DIM_THEN_1]], 8]
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map0, #map1]
  //     CHECK-SAME: ins(%arg0 : tensor<8x1x1xi1>) outs(%[[INIT_PRED]] : tensor<8x?x8xi1>)
  // CHECK: %[[INIT_THEN:.*]] = linalg.init_tensor [8, %[[DIM_THEN_1]], 8]
  // CHECK: %[[BCAST_THEN:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map2, #map1]
  //     CHECK-SAME: ins(%arg1 : tensor<1x?x1xi32>) outs(%[[INIT_THEN]] : tensor<8x?x8xi32>)
  // CHECK: %[[INIT_ELSE:.*]] = linalg.init_tensor [8, %[[DIM_THEN_1]], 8]
  // CHECK: %[[BCAST_ELSE:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map3, #map1]
  //     CHECK-SAME: ins(%arg2 : tensor<1x1x8xi32>) outs(%[[INIT_ELSE]] : tensor<8x?x8xi32>)
  // CHECK: %[[C1_1:.*]] = constant 1 : index
  // CHECK: %[[DIM_BCAST_PRED_1:.*]] = memref.dim %[[BCAST_PRED]], %[[C1_1]]
  // CHECK: %[[INIT_RESULT:.*]] = linalg.init_tensor [8, %[[DIM_BCAST_PRED_1]], 8]
  // CHECK: linalg.generic
  //     CHECK-SAME: ins(%2, %4, %6 : tensor<8x?x8xi1>, tensor<8x?x8xi32>, tensor<8x?x8xi32>) outs(%8 : tensor<8x?x8xi32>)
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<8x1x1xi1>, tensor<1x?x1xi32>, tensor<1x1x8xi32>) -> tensor<8x?x8xi32>
  return %0: tensor<8x?x8xi32>
}

// -----
// CHECK-LABEL: func @selectv2_broadcast_dyn_else
func @selectv2_broadcast_dyn_else(%arg0: tensor<8x1x1xi1>, %arg1: tensor<1x8x1xi32>, %arg2: tensor<1x1x?xi32>) -> tensor<8x8x?xi32> {
  // CHECK: %[[C2_0:.*]] = constant 2 : index
  // CHECK: %[[DIM_ELSE_2:.*]] = memref.dim %arg2, %[[C2_0]]
  // CHECK: %[[INIT_PRED:.*]] = linalg.init_tensor [8, 8, %[[DIM_ELSE_2]]]
  // CHECK: %[[BCAST_PRED:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map0, #map1]
  //     CHECK-SAME: ins(%arg0 : tensor<8x1x1xi1>) outs(%[[INIT_PRED]] : tensor<8x8x?xi1>)

  // CHECK: %[[INIT_THEN:.*]] = linalg.init_tensor [8, 8, %[[DIM_ELSE_2]]]
  // CHECK: %[[BCAST_THEN:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map2, #map1]
  //     CHECK-SAME: ins(%arg1 : tensor<1x8x1xi32>) outs(%[[INIT_THEN]] : tensor<8x8x?xi32>)
  // CHECK: %[[INIT_ELSE:.*]] = linalg.init_tensor [8, 8, %[[DIM_ELSE_2]]]
  // CHECK: %[[BCAST_ELSE:.*]] = linalg.generic
  //     CHECK-SAME: indexing_maps = [#map3, #map1]
  //     CHECK-SAME: ins(%arg2 : tensor<1x1x?xi32>) outs(%[[INIT_ELSE]] : tensor<8x8x?xi32>)
  // CHECK: %[[C2_1:.*]] = constant 2 : index
  // CHECK: %[[DIM_BCAST_PRED_1:.*]] = memref.dim %[[BCAST_PRED]], %[[C2_1]]
  // CHECK: %[[INIT_RESULT:.*]] = linalg.init_tensor [8, 8, %[[DIM_BCAST_PRED_1]]]
  // CHECK: linalg.generic
  //     CHECK-SAME: ins(%2, %4, %6 : tensor<8x8x?xi1>, tensor<8x8x?xi32>, tensor<8x8x?xi32>) outs(%8 : tensor<8x8x?xi32>)
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<8x1x1xi1>, tensor<1x8x1xi32>, tensor<1x1x?xi32>) -> tensor<8x8x?xi32>
  return %0: tensor<8x8x?xi32>
}

// -----
// CHECK-LABEL: func @selectv2_broadcast_dyn_all
func @selectv2_broadcast_dyn_all(%arg0: tensor<?x1x1xi1>, %arg1: tensor<?x8x1xi32>, %arg2: tensor<?x1x?xi32>) -> tensor<?x8x?xi32> {
  // CHECK: %[[C0:.*]] = constant 0 : index
  // CHECK: %[[PRED_D0:.*]] = memref.dim %arg0, %[[C0]] : tensor<?x1x1xi1>
  // CHECK: %[[C0_0:.*]] = constant 0 : index
  // CHECK: %[[THEN_D0:.*]] = memref.dim %arg1, %[[C0_0]] : tensor<?x8x1xi32>
  // CHECK: %[[C0_1:.*]] = constant 0 : index
  // CHECK: %[[ELSE_D0:.*]] = memref.dim %arg2, %[[C0_1]] : tensor<?x1x?xi32>
  // CHECK: %[[C2:.*]] = constant 2 : index
  // CHECK: %[[ELSE_D2:.*]] = memref.dim %arg2, %[[C2]] : tensor<?x1x?xi32>
  // CHECK: %[[CMP_0:.*]] = cmpi eq, %[[PRED_D0]], %[[THEN_D0]] : index
  // CHECK: assert %[[CMP_0]], "mismatched dynamic broadcast extents"
  // CHECK: %[[CMP_1:.*]] = cmpi eq, %[[PRED_D0]], %[[ELSE_D0]] : index
  // CHECK: assert %[[CMP_1]], "mismatched dynamic broadcast extents"
  // Only two asserts are needed. The rest are statically verified.
  // CHECK-NOT: assert
  %0 = "chlo.broadcast_select"(%arg0, %arg1, %arg2) : (tensor<?x1x1xi1>, tensor<?x8x1xi32>, tensor<?x1x?xi32>) -> tensor<?x8x?xi32>
  return %0: tensor<?x8x?xi32>
}

// -----
// Note that broadcast_add is used as a proxy for all of the template
// expansions. Tests below merely verify that the op has an expansion.
// CHECK-LABEL: @andWithoutBroadcast
func @andWithoutBroadcast(%arg0: tensor<4xi1>, %arg1: tensor<4xi1>) -> tensor<4xi1> {
  // CHECK-NOT: mhlo.and
  %0 = chlo.broadcast_and %arg0, %arg1 : (tensor<4xi1>, tensor<4xi1>) -> tensor<4xi1>
  return %0 : tensor<4xi1>
}

// -----
// CHECK-LABEL: @atan2WithoutBroadcast
func @atan2WithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.atan2
  %0 = chlo.broadcast_atan2 %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @compareWithoutBroadcast
func @compareWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xi1> {
  // CHECK-NOT: mhlo.compare
  %0 = chlo.broadcast_compare %arg0, %arg1 {comparison_direction = "EQ"} : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xi1>
  return %0 : tensor<4xi1>
}

// -----
// CHECK-LABEL: @complexWithoutBroadcast
func @complexWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> (tensor<4xf32>, tensor<4xf32>) {
  // CHECK-NOT: mhlo.complex
  // CHECK-NOT: chlo.broadcast_complex
  %0 = chlo.broadcast_complex %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xcomplex<f32>>

  %1 = "mhlo.real"(%0) : (tensor<4xcomplex<f32>>) -> tensor<4xf32>
  %2 = "mhlo.imag"(%0) : (tensor<4xcomplex<f32>>) -> tensor<4xf32>

  return %1, %2 : tensor<4xf32>, tensor<4xf32>
}

// -----
// CHECK-LABEL: @divideWithoutBroadcast
func @divideWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.divide
  %0 = chlo.broadcast_divide %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @maximumWithoutBroadcast
func @maximumWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.maximum
  %0 = chlo.broadcast_maximum %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @minimumWithoutBroadcast
func @minimumWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.minimum
  %0 = chlo.broadcast_minimum %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @multiplyWithoutBroadcast
func @multiplyWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.multiply
  %0 = chlo.broadcast_multiply %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @orWithoutBroadcast
func @orWithoutBroadcast(%arg0: tensor<4xi1>, %arg1: tensor<4xi1>) -> tensor<4xi1> {
  // CHECK-NOT: mhlo.or
  %0 = chlo.broadcast_or %arg0, %arg1 : (tensor<4xi1>, tensor<4xi1>) -> tensor<4xi1>
  return %0 : tensor<4xi1>
}

// -----
// CHECK-LABEL: @powerWithoutBroadcast
func @powerWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.power
  %0 = chlo.broadcast_power %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @remainderWithoutBroadcast
func @remainderWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.remainder
  %0 = chlo.broadcast_remainder %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @subWithoutBroadcast
func @subWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>) -> tensor<4xf32> {
  // CHECK-NOT: mhlo.subtract
  %0 = chlo.broadcast_subtract %arg0, %arg1 : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @xorWithoutBroadcast
func @xorWithoutBroadcast(%arg0: tensor<4xi1>, %arg1: tensor<4xi1>) -> tensor<4xi1> {
  // CHECK-NOT: mhlo.xor
  %0 = chlo.broadcast_xor %arg0, %arg1 : (tensor<4xi1>, tensor<4xi1>) -> tensor<4xi1>
  return %0 : tensor<4xi1>
}

// -----
// CHECK-LABEL: @ZetaWithoutBroadcast
func @ZetaWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>)
    -> tensor<4xf32> {
  // This is a composition: it should lower completely.
  // CHECK-NOT: mhlo.
  %0 = chlo.broadcast_zeta %arg0, %arg1
      : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}

// -----
// CHECK-LABEL: @PolygammaWithoutBroadcast
// CHECK-SAME: (%[[LHS:.*]]: tensor<4xf32>, %[[RHS:.*]]: tensor<4xf32>)
func @PolygammaWithoutBroadcast(%arg0: tensor<4xf32>, %arg1: tensor<4xf32>)
    -> tensor<4xf32> {
  // This is a composition: it should lower completely.
  // CHECK-NOT: mhlo.
  %0 = chlo.broadcast_polygamma %arg0, %arg1
      : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
  return %0 : tensor<4xf32>
}
