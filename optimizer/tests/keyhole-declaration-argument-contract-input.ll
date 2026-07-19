target datalayout = "e-p:64:64:64"

define i32 @memcmp_declaration_argument_contract(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  ret i32 %result
}

declare noundef i32 @memcmp(ptr noundef captures(none), ptr captures(none), i64)
