#include "_lib_a.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main() { let v = lib_a_value(); }
