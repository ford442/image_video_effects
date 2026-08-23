// Fixture: invocation product 17*16 = 272 > 256
@compute @workgroup_size(17, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  _ = gid;
}
