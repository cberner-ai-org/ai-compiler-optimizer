target datalayout = "e-p:64:64:64"

define i64 @ordered_binary_search_trunc_nsw(i64 %count, i1 %take_upper) {
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
  %midpoint = trunc nsw i128 %half.wide to i64
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

define i64 @ordered_binary_search_trunc_nuw_nsw(i64 %count, i1 %take_upper) {
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
  %midpoint = trunc nuw nsw i128 %half.wide to i64
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
