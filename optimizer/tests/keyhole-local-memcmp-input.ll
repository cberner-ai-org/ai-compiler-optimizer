target datalayout = "e-p:64:64:64"

define i32 @memcmp(ptr captures(none) %left, ptr captures(none) %right, i64 %length) {
entry:
  ret i32 7
}

define i32 @call_module_memcmp(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  ret i32 %result
}
