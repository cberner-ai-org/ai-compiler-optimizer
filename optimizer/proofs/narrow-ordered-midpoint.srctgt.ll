target datalayout = "e-p:64:64:64"

define i64 @src(i64 %minimum, i64 %maximum) {
entry:
  %ordered = icmp ult i64 %minimum, %maximum
  br i1 %ordered, label %midpoint, label %exit

midpoint:
  %minimum_wide = zext i64 %minimum to i128
  %maximum_wide = zext i64 %maximum to i128
  %sum_wide = add nuw nsw i128 %minimum_wide, %maximum_wide
  %half_wide = lshr i128 %sum_wide, 1
  %result = trunc nuw i128 %half_wide to i64
  br label %exit

exit:
  %value = phi i64 [ %result, %midpoint ], [ 0, %entry ]
  ret i64 %value
}

define i64 @tgt(i64 %minimum, i64 %maximum) {
entry:
  %ordered = icmp ult i64 %minimum, %maximum
  br i1 %ordered, label %midpoint, label %exit

midpoint:
  %delta = sub nuw i64 %maximum, %minimum
  %half_delta = lshr i64 %delta, 1
  %result = add nuw i64 %minimum, %half_delta
  br label %exit

exit:
  %value = phi i64 [ %result, %midpoint ], [ 0, %entry ]
  ret i64 %value
}
