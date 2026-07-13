// Fixture: single override arg (must warn, never auto-fix)
const block_width = 16u;

@compute @workgroup_size(block_width)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  _ = gid;
}
