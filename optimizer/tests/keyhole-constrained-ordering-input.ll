target datalayout = "e-p:64:64:64"

define i8 @slice_compare_ordering_musttail(i64 %left.bits, i64 %right.bits) {
entry:
  %left = inttoptr i64 %left.bits to ptr
  %right = inttoptr i64 %right.bits to ptr
  %length = call i64 @llvm.umin.i64(i64 %left.bits, i64 %right.bits)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  %comparison.extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length.difference = sub i64 %left.bits, %right.bits
  %difference = select i1 %equal, i64 %length.difference, i64 %comparison.extended
  %ordering = musttail call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  ret i8 %ordering
}

define i8 @slice_compare_ordering_convergent(i64 %left.bits, i64 %right.bits) {
entry:
  %left = inttoptr i64 %left.bits to ptr
  %right = inttoptr i64 %right.bits to ptr
  %length = call i64 @llvm.umin.i64(i64 %left.bits, i64 %right.bits)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  %comparison.extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length.difference = sub i64 %left.bits, %right.bits
  %difference = select i1 %equal, i64 %length.difference, i64 %comparison.extended
  %ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0) convergent
  ret i8 %ordering
}

define i8 @slice_compare_ordering_notail(i64 %left.bits, i64 %right.bits) {
entry:
  %left = inttoptr i64 %left.bits to ptr
  %right = inttoptr i64 %right.bits to ptr
  %length = call i64 @llvm.umin.i64(i64 %left.bits, i64 %right.bits)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  %comparison.extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length.difference = sub i64 %left.bits, %right.bits
  %difference = select i1 %equal, i64 %length.difference, i64 %comparison.extended
  %ordering = notail call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  ret i8 %ordering
}

define i8 @slice_compare_ordering_tail_hint(i64 %left.bits, i64 %right.bits) {
entry:
  %left = inttoptr i64 %left.bits to ptr
  %right = inttoptr i64 %right.bits to ptr
  %length = call i64 @llvm.umin.i64(i64 %left.bits, i64 %right.bits)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  %comparison.extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length.difference = sub i64 %left.bits, %right.bits
  %difference = select i1 %equal, i64 %length.difference, i64 %comparison.extended
  %ordering = tail call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  ret i8 %ordering
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)
declare i64 @llvm.umin.i64(i64, i64)
declare i8 @llvm.scmp.i8.i64(i64, i64)
