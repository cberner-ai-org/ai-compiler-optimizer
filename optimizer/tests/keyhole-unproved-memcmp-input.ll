target datalayout = "e-m:e-p:32:32-i64:64-n8:16:32-S128"
target triple = "i686-unknown-linux-gnu"

define i32 @memcmp_i686(ptr %left, ptr %right, i32 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i32 %length)
  ret i32 %result
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i32)
