fn main() {
    let sum: u64 = (1..=100).sum();
    assert_eq!(sum, 5_050);
    println!("custom rustc smoke test passed");
}
