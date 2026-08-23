// Commented attribute must not trigger convention warning
// @workgroup_size(8, 8)
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  _ = gid;
}
