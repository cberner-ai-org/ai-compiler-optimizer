target datalayout = "e-p:64:64:64"

define i32 @memcmp_proved_nonnull(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr nonnull %left, ptr nonnull %right, i64 %length)
  ret i32 %result
}

define i32 @memcmp_unproved_partial_nonnull(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr nonnull %left, ptr %right, i64 %length)
  ret i32 %result
}

define i32 @memcmp_unproved_dereferenceable(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr dereferenceable(8) %left, ptr %right, i64 %length)
  ret i32 %result
}

define i32 @memcmp_unproved_alignment(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr align 8 %left, ptr %right, i64 %length)
  ret i32 %result
}

define i32 @memcmp_unproved_noundef(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call noundef i32 @memcmp(ptr noundef nonnull %left, ptr noundef nonnull %right, i64 noundef %length)
  ret i32 %result
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)
