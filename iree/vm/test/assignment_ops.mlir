vm.module @assignment_ops {

  //===--------------------------------------------------------------------===//
  // Conditional assignment
  //===--------------------------------------------------------------------===//

  vm.export @test_select_i32
  vm.func @test_select_i32() {
    %c0 = vm.const.i32 0 : i32
    %c0dno = iree.do_not_optimize(%c0) : i32
    %c1 = vm.const.i32 1 : i32
    %c1dno = iree.do_not_optimize(%c1) : i32
    %v1 = vm.select.i32 %c0dno, %c0dno, %c1dno : i32
    vm.check.eq %v1, %c1, "0 ? 0 : 1 = 1" : i32
    %v2 = vm.select.i32 %c1dno, %c0dno, %c1dno : i32
    vm.check.eq %v2, %c0, "1 ? 0 : 1 = 0" : i32
    vm.return
  }

  vm.export @test_select_ref
  vm.func @test_select_ref() {
    %c0 = vm.const.i32 0 : i32
    %list0 = vm.list.alloc %c0 : (i32) -> !vm.list<i8>
    %c1 = vm.const.i32 1 : i32
    %list1 = vm.list.alloc %c1 : (i32) -> !vm.list<i8>
    %cond = vm.const.i32 0 : i32
    %cond_dno = iree.do_not_optimize(%cond) : i32
    %list = vm.select.ref %cond_dno, %list0, %list1 : !vm.list<i8>
    vm.check.eq %list, %list1, "0 ? list0 : list1 = list1" : !vm.list<i8>
    vm.return
  }
}
