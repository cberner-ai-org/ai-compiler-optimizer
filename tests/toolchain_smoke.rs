#[inline(never)]
fn compare(left: &[u8], right: &[u8]) -> std::cmp::Ordering {
    left.cmp(right)
}

fn main() {
    let sum: u64 = (1..=100).sum();
    assert_eq!(sum, 5_050);
    assert_eq!(compare(b"alpha", b"bravo"), std::cmp::Ordering::Less);
    assert_eq!(compare(b"bravo", b"alpha"), std::cmp::Ordering::Greater);
    assert_eq!(compare(b"equal", b"equal"), std::cmp::Ordering::Equal);
    assert_eq!(compare(b"", b""), std::cmp::Ordering::Equal);
    println!("custom rustc smoke test passed");
}
