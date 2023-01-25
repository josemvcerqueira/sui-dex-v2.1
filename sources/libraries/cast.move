module ipx::cast {
  const CAST_ERROR_u128_u64: u64 = 80;
  const U64_MAX: u128 = 18446744073709551615;

  public fun cast_to_u64(x: u128): u64 {
    assert!(x <= U64_MAX, CAST_ERROR_u128_u64);
    (x as u64)
  }
}