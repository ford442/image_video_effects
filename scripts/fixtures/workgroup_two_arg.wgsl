// Fixture: two-arg literal workgroup (project convention violation)
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  _ = gid;
}
