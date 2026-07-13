// Fixture: two-arg literal workgroup (now permitted; 2-arg accepted, Z defaults to 1)
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  _ = gid;
}
