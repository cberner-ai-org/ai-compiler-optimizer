; Freezing a pointer refines its one source use. Applying this obligation once
; per memcmp pointer gives the noundef intermediate modeled by the first-byte
; proofs, where each frozen value is shared by the load and retained call.
define ptr @src(ptr %pointer) {
entry:
  ret ptr %pointer
}

define ptr @tgt(ptr %pointer) {
entry:
  %frozen = freeze ptr %pointer
  ret ptr %frozen
}
