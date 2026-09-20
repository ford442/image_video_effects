#include "_lib_a.wgsl"
fn lib_b_value() -> f32 { return lib_a_value() + 1.0; }
