target datalayout = "e-p:64:64:64"

define i32 @memcmp_declaration_argmem_readwrite(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
  ret i32 %result
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64) memory(argmem: readwrite)
