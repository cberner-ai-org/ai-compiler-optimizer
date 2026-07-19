declare i8 @llvm.scmp.i8.i64(i64, i64)
declare i8 @llvm.scmp.i8.i32(i32, i32)

define i32 @signed_i64(i64 %left, i64 %right) {
entry:
  %cmp = call i8 @llvm.scmp.i8.i64(i64 %left, i64 %right)
  switch i8 %cmp, label %invalid [
    i8 -1, label %less
    i8 0, label %equal
    i8 1, label %greater
  ]

less:
  %less.result = phi i32 [ -1, %entry ]
  ret i32 %less.result

equal:
  %equal.result = phi i32 [ 0, %entry ]
  ret i32 %equal.result

greater:
  %greater.result = phi i32 [ 1, %entry ]
  ret i32 %greater.result

invalid:
  unreachable
}

define i32 @signed_i64_undef(i64 %right) {
entry:
  %cmp = call i8 @llvm.scmp.i8.i64(i64 undef, i64 %right)
  switch i8 %cmp, label %invalid [
    i8 -1, label %less
    i8 0, label %equal
    i8 1, label %greater
  ]

less:
  ret i32 -1

equal:
  ret i32 0

greater:
  ret i32 1

invalid:
  unreachable
}

define i32 @hoisted_i64(i64 %left, i64 %right, i1 %repeat) {
entry:
  %cmp = call i8 @llvm.scmp.i8.i64(i64 %left, i64 %right)
  br label %dispatch

dispatch:
  switch i8 %cmp, label %invalid [
    i8 -1, label %less
    i8 0, label %equal
    i8 1, label %greater
  ]

less:
  br i1 %repeat, label %dispatch, label %less.exit

less.exit:
  ret i32 -1

equal:
  br i1 %repeat, label %dispatch, label %equal.exit

equal.exit:
  ret i32 0

greater:
  br i1 %repeat, label %dispatch, label %greater.exit

greater.exit:
  ret i32 1

invalid:
  unreachable
}

define i32 @unsupported_i32(i32 %left, i32 %right) {
entry:
  %cmp = call i8 @llvm.scmp.i8.i32(i32 %left, i32 %right)
  switch i8 %cmp, label %invalid [
    i8 -1, label %less
    i8 0, label %equal
    i8 1, label %greater
  ]

less:
  ret i32 -1

equal:
  ret i32 0

greater:
  ret i32 1

invalid:
  unreachable
}

define i32 @noncanonical_i64(i64 %left, i64 %right) {
entry:
  %cmp = call i8 @llvm.scmp.i8.i64(i64 %left, i64 %right)
  switch i8 %cmp, label %other [
    i8 -1, label %less
    i8 0, label %equal
  ]

less:
  ret i32 -1

equal:
  ret i32 0

other:
  ret i32 1
}
