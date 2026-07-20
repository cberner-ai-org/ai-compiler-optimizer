target datalayout = "e-p:64:64:64"

define i8 @slice_compare_with_interleaved_convergent(ptr %left, i64 %left.length, ptr %right, i64 %right.length) {
entry:
  %length = call i64 @llvm.umin.i64(i64 %left.length, i64 %right.length)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  call void @side_effect() convergent
  %comparison.extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length.difference = sub i64 %left.length, %right.length
  %difference = select i1 %equal, i64 %length.difference, i64 %comparison.extended
  %ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  ret i8 %ordering
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)
declare void @side_effect()
declare i64 @llvm.umin.i64(i64, i64)
declare i8 @llvm.scmp.i8.i64(i64, i64)
