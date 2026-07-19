define i64 @match_with_flags(i64 %left, i64 %right) {
  %left.wide = zext i64 %left to i128
  %right.wide = zext i64 %right to i128
  %sum = add nuw nsw i128 %left.wide, %right.wide
  %half = lshr i128 %sum, 1
  %result = trunc nuw i128 %half to i64
  ret i64 %result
}

define i64 @wrong_shift(i64 %left, i64 %right) {
  %left.wide = zext i64 %left to i128
  %right.wide = zext i64 %right to i128
  %sum = add i128 %left.wide, %right.wide
  %quarter = lshr i128 %sum, 2
  %result = trunc i128 %quarter to i64
  ret i64 %result
}

define i64 @match_without_flags(i64 %a, i64 %b) {
  %a.wide = zext i64 %a to i128
  %b.wide = zext i64 %b to i128
  %sum = add i128 %b.wide, %a.wide
  %half = lshr i128 %sum, 1
  %result = trunc i128 %half to i64
  ret i64 %result
}

define i32 @wrong_result_width(i64 %left, i64 %right) {
  %left.wide = zext i64 %left to i128
  %right.wide = zext i64 %right to i128
  %sum = add i128 %left.wide, %right.wide
  %half = lshr i128 %sum, 1
  %result = trunc i128 %half to i32
  ret i32 %result
}
