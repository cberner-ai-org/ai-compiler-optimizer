target datalayout = "e-p:64:64:64"

; This is the unequal-first-byte case of the second refinement used by the
; slice-comparison specialization. Together with the zero-length and
; equal-first-byte obligations, it is an exhaustive partition.
; The first refinement, which expands memcmp into this three-way CFG, is
; proved independently in memcmp-first-byte.srctgt.ll.
define i8 @src(ptr noundef captures(none) %left, i64 %left_length, ptr noundef captures(none) %right, i64 %right_length) {
entry:
  %length = call i64 @llvm.umin.i64(i64 %left_length, i64 %right_length)
  %length_frozen = freeze i64 %length
  %nonempty = icmp ne i64 %length_frozen, 0
  call void @llvm.assume(i1 %nonempty)
  br i1 %nonempty, label %check_first, label %compare_join

check_first:
  %left_byte = load i8, ptr %left, align 1
  %right_byte = load i8, ptr %right, align 1
  %left_frozen = freeze i8 %left_byte
  %right_frozen = freeze i8 %right_byte
  %first_equal = icmp eq i8 %left_frozen, %right_frozen
  %first_unequal = xor i1 %first_equal, true
  call void @llvm.assume(i1 %first_unequal)
  br i1 %first_equal, label %slow, label %fast

slow:
  %slow_comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length_frozen)
  br label %compare_join

fast:
  %left_extended = zext i8 %left_frozen to i32
  %right_extended = zext i8 %right_frozen to i32
  %fast_comparison = sub nsw i32 %left_extended, %right_extended
  br label %compare_join

compare_join:
  %comparison = phi i32 [ 0, %entry ], [ %slow_comparison, %slow ], [ %fast_comparison, %fast ]
  %comparison_extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length_difference = sub i64 %left_length, %right_length
  %difference = select i1 %equal, i64 %length_difference, i64 %comparison_extended
  %ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  ret i8 %ordering
}

define i8 @tgt(ptr noundef captures(none) %left, i64 %left_length, ptr noundef captures(none) %right, i64 %right_length) {
entry:
  %length = call i64 @llvm.umin.i64(i64 %left_length, i64 %right_length)
  %length_frozen = freeze i64 %length
  %nonempty = icmp ne i64 %length_frozen, 0
  call void @llvm.assume(i1 %nonempty)
  br i1 %nonempty, label %check_first, label %slow

check_first:
  %left_byte = load i8, ptr %left, align 1
  %right_byte = load i8, ptr %right, align 1
  %left_frozen = freeze i8 %left_byte
  %right_frozen = freeze i8 %right_byte
  %first_equal = icmp eq i8 %left_frozen, %right_frozen
  %first_unequal = xor i1 %first_equal, true
  call void @llvm.assume(i1 %first_unequal)
  br i1 %first_equal, label %slow, label %fast

slow:
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length_frozen)
  %comparison_extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length_difference = sub i64 %left_length, %right_length
  %difference = select i1 %equal, i64 %length_difference, i64 %comparison_extended
  %slow_ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  br label %join

fast:
  %first_less = icmp ult i8 %left_frozen, %right_frozen
  %fast_ordering = select i1 %first_less, i8 -1, i8 1
  br label %join

join:
  %ordering = phi i8 [ %fast_ordering, %fast ], [ %slow_ordering, %slow ]
  ret i8 %ordering
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)
declare i64 @llvm.umin.i64(i64, i64)
declare i8 @llvm.scmp.i8.i64(i64, i64)
declare void @llvm.assume(i1)
