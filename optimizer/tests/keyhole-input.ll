target datalayout = "e-p:64:64:64"

define i64 @ordered_binary_search(i64 %count, i1 %take_upper) {
entry:
  %nonempty = icmp ne i64 %count, 0
  br i1 %nonempty, label %preheader, label %exit

preheader:
  br label %loop

loop:
  %minimum = phi i64 [ 0, %preheader ], [ %minimum.next, %backedge ]
  %maximum = phi i64 [ %count, %preheader ], [ %maximum.next, %backedge ]
  %minimum.wide = zext i64 %minimum to i128
  %maximum.wide = zext i64 %maximum to i128
  %sum.wide = add nuw nsw i128 %minimum.wide, %maximum.wide
  %half.wide = lshr i128 %sum.wide, 1
  %midpoint = trunc nuw i128 %half.wide to i64
  %midpoint.next = add nuw i64 %midpoint, 1
  br i1 %take_upper, label %upper, label %lower

upper:
  br label %backedge

lower:
  br label %backedge

backedge:
  %minimum.next = phi i64 [ %midpoint.next, %upper ], [ %minimum, %lower ]
  %maximum.next = phi i64 [ %maximum, %upper ], [ %midpoint, %lower ]
  %again = icmp ult i64 %minimum.next, %maximum.next
  br i1 %again, label %loop, label %exit

exit:
  %result = phi i64 [ 0, %entry ], [ %minimum.next, %backedge ]
  ret i64 %result
}

define i64 @unguarded_binary_search(i64 %count, i1 %take_upper) {
entry:
  br label %loop

loop:
  %minimum = phi i64 [ 0, %entry ], [ %minimum.next, %backedge ]
  %maximum = phi i64 [ %count, %entry ], [ %maximum.next, %backedge ]
  %minimum.wide = zext i64 %minimum to i128
  %maximum.wide = zext i64 %maximum to i128
  %sum.wide = add nuw nsw i128 %minimum.wide, %maximum.wide
  %half.wide = lshr i128 %sum.wide, 1
  %midpoint = trunc nuw i128 %half.wide to i64
  %midpoint.next = add nuw i64 %midpoint, 1
  br i1 %take_upper, label %upper, label %lower

upper:
  br label %backedge

lower:
  br label %backedge

backedge:
  %minimum.next = phi i64 [ %midpoint.next, %upper ], [ %minimum, %lower ]
  %maximum.next = phi i64 [ %maximum, %upper ], [ %midpoint, %lower ]
  %again = icmp ult i64 %minimum.next, %maximum.next
  br i1 %again, label %loop, label %exit

exit:
  ret i64 %minimum.next
}

define i32 @memcmp_candidate(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  ret i32 %result
}

define i32 @memcmp_undef_pointers(i64 %length) {
entry:
  %result = call i32 @memcmp(ptr undef, ptr undef, i64 %length)
  ret i32 %result
}

define i32 @memcmp_convergent(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length) convergent
  ret i32 %result
}

define i32 @memcmp_musttail(ptr %left, ptr %right, i64 %length) {
entry:
  %result = musttail call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  ret i32 %result
}

define i32 @memcmp_notail(ptr %left, ptr %right, i64 %length) {
entry:
  %result = notail call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  ret i32 %result
}

define i8 @slice_compare_candidate(ptr %left, i64 %left.length, ptr %right, i64 %right.length) {
entry:
  %length = call i64 @llvm.umin.i64(i64 %left.length, i64 %right.length)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  %comparison.extended = sext i32 %comparison to i64
  %equal = icmp eq i32 %comparison, 0
  %length.difference = sub i64 %left.length, %right.length
  %difference = select i1 %equal, i64 %length.difference, i64 %comparison.extended
  %ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
  switch i8 %ordering, label %invalid [
    i8 -1, label %less
    i8 0, label %equal.result
    i8 1, label %greater
  ]

less:
  ret i8 -1

equal.result:
  ret i8 0

greater:
  ret i8 1

invalid:
  unreachable
}

define i8 @slice_compare_with_interleaved_side_effect(ptr %left, i64 %left.length, ptr %right, i64 %right.length) {
entry:
  %length = call i64 @llvm.umin.i64(i64 %left.length, i64 %right.length)
  %comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  call void @side_effect()
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
