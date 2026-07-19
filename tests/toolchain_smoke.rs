unsafe extern "C" {
    fn memcmp(left: *const u8, right: *const u8, length: usize) -> i32;
}

#[inline(never)]
fn compare(left: &[u8], right: &[u8]) -> i32 {
    assert_eq!(left.len(), right.len());
    unsafe { memcmp(left.as_ptr(), right.as_ptr(), left.len()) }
}

fn main() {
    let sum: u64 = (1..=100).sum();
    assert_eq!(sum, 5_050);
    assert!(compare(b"alpha", b"bravo") < 0);
    assert!(compare(b"bravo", b"alpha") > 0);
    assert_eq!(compare(b"equal", b"equal"), 0);
    assert_eq!(compare(b"", b""), 0);
    println!("custom rustc smoke test passed");
}
