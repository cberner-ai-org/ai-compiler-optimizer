target datalayout = "e-p:64:64:64"

define i32 @memcmp_result_range(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length), !range !0
  ret i32 %result
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)

!0 = !{i32 -1, i32 2}
