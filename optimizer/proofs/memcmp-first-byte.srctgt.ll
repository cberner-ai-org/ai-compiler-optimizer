target datalayout = "e-p:64:64:64"

define i32 @src(ptr captures(none) %left, ptr captures(none) %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  ret i32 %result
}

define i32 @tgt(ptr captures(none) %left, ptr captures(none) %right, i64 %length) {
entry:
  %length_frozen = freeze i64 %length
  %nonempty = icmp ne i64 %length_frozen, 0
  br i1 %nonempty, label %check_first, label %join

check_first:
  %left_byte = load i8, ptr %left, align 1
  %right_byte = load i8, ptr %right, align 1
  %left_frozen = freeze i8 %left_byte
  %right_frozen = freeze i8 %right_byte
  %first_equal = icmp eq i8 %left_frozen, %right_frozen
  br i1 %first_equal, label %slow, label %fast

slow:
  %slow_result = call i32 @memcmp(ptr %left, ptr %right, i64 %length_frozen)
  br label %join

fast:
  %left_extended = zext i8 %left_frozen to i32
  %right_extended = zext i8 %right_frozen to i32
  %difference = sub nsw i32 %left_extended, %right_extended
  br label %join

join:
  %result = phi i32 [ 0, %entry ], [ %slow_result, %slow ], [ %difference, %fast ]
  ret i32 %result
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)
