target datalayout = "e-p:64:64:64"

define i32 @memcmp_call_memory_none(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length) memory(none)
  ret i32 %result
}

define i32 @memcmp_call_inaccessible_memory(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length) memory(inaccessiblemem: readwrite)
  ret i32 %result
}

define i32 @memcmp_call_argmem_readwrite(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length) memory(argmem: readwrite)
  ret i32 %result
}

define i32 @memcmp_call_argmem_read_inaccessible_write(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length) memory(argmem: read, inaccessiblemem: write)
  ret i32 %result
}

define i32 @memcmp_call_argmem_read(ptr %left, ptr %right, i64 %length) {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %length) memory(argmem: read)
  ret i32 %result
}

declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)
