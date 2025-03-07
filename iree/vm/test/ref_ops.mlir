vm.module @ref_ops {
  vm.rodata private @buffer_i8 dense<[1, 2, 3]> : tensor<3xi8>
  vm.rodata private @buffer_i32 dense<[1, 2, 3]> : tensor<3xi32>

  vm.export @test_zero_ref_eq
  vm.func @test_zero_ref_eq() {
    %ref = vm.const.ref.zero : !vm.ref<?>
    %ref_dno = iree.do_not_optimize(%ref) : !vm.ref<?>
    vm.check.eq %ref_dno, %ref_dno : !vm.ref<?>
    vm.return
  }

  vm.export @test_ref_eq
  vm.func @test_ref_eq() {
    %ref_1 = vm.const.ref.rodata @buffer_i8 : !vm.buffer
    %ref_1_dno = iree.do_not_optimize(%ref_1) : !vm.buffer
    %ref_2 = vm.const.ref.rodata @buffer_i8 : !vm.buffer
    %ref_2_dno = iree.do_not_optimize(%ref_2) : !vm.buffer
    vm.check.eq %ref_1_dno, %ref_2_dno : !vm.buffer
    vm.return
  }

  vm.export @test_ref_ne
  vm.func @test_ref_ne() {
    %ref_i8 = vm.const.ref.rodata @buffer_i8 : !vm.buffer
    %ref_i8_dno = iree.do_not_optimize(%ref_i8) : !vm.buffer
    %ref_i32 = vm.const.ref.rodata @buffer_i32 : !vm.buffer
    %ref_i32_dno = iree.do_not_optimize(%ref_i32) : !vm.buffer
    vm.check.ne %ref_i8_dno, %ref_i32_dno : !vm.buffer
    vm.return
  }

  vm.export @test_ref_nz
  vm.func @test_ref_nz() {
    %ref = vm.const.ref.rodata @buffer_i8 : !vm.buffer
    %ref_dno = iree.do_not_optimize(%ref) : !vm.buffer
    vm.check.nz %ref_dno : !vm.buffer
    vm.return
  }

}
