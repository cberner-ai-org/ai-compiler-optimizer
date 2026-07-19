target datalayout = "e-p:64:64:64"

; Zero-length case of the second slice-comparison refinement. The expanded
; memcmp produces zero directly; the specialized CFG enters its slow path.
define i8 @src(ptr captures(none) %left, i64 %left_length, ptr captures(none) %right, i64 %right_length) {
entry:
  %length = call i64 @llvm.umin.i64(i64 %left_length, i64 %right_length)
  %length_frozen = freeze i64 %length
  %empty = icmp eq i64 %length_frozen, 0
  call void @llvm.assume(i1 %empty)
  %comparison_extended = sext i32 0 to i64
  %equal = icmp eq i32 0, 0
  %length_difference = sub i64 %left_length, %right_length
  %difference = select i1 %equal, i64 %length_difference, i64 %comparison_extended
  %ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  ret i8 %ordering
}

define i8 @tgt(ptr captures(none) %left, i64 %left_length, ptr captures(none) %right, i64 %right_length) {
entry:
  %length = call i64 @llvm.umin.i64(i64 %left_length, i64 %right_length)
  %length_frozen = freeze i64 %length
  %empty = icmp eq i64 %length_frozen, 0
  call void @llvm.assume(i1 %empty)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length_frozen)
  %comparison_extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length_difference = sub i64 %left_length, %right_length
  %difference = select i1 %equal, i64 %length_difference, i64 %comparison_extended
  %ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  ret i8 %ordering
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)
declare i64 @llvm.umin.i64(i64, i64)
declare i8 @llvm.scmp.i8.i64(i64, i64)
declare void @llvm.assume(i1)
