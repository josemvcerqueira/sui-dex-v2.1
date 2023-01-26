module ipx::math {
  
  use ipx::cast::{cast_to_u64};

  public fun mul_to_u128(x: u64, y:u64): u128 {
    (x as u128) * (y as u128)
  }

  public fun mul_div(x: u64, y: u64, z: u64): u64 {
    cast_to_u64(mul_to_u128(x, y) / (z as u128))
  }
}