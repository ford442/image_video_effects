// ═══════════════════════════════════════════════════════════════
//  Mirror Dimension
//  A kaleidoscope effect with rotating axes controllable by mouse.
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Segments, y=RotationSpeed, z=Offset, w=Zoom
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let segments = floor(mix(2.0, 12.0, u.zoom_params.x));
    let rotSpeed = mix(-1.0, 1.0, u.zoom_params.y);
    let offsetVal = u.zoom_params.z;
    let zoom = mix(0.5, 2.0, u.zoom_params.w);

    // Center UV
    var p = uv - 0.5;

    // Correct Aspect?
    // Kaleidoscopes often look better if we work in square space then stretch back
    // or just distort everything. Let's correct aspect for rotation at least.
    let aspect = resolution.x / resolution.y;
    p.x *= aspect;

    // Mouse Interaction: Mouse position offsets the center of symmetry?
    // Or adds to rotation?
    let mouse = u.zoom_config.yz;
    if (u.zoom_config.y > 0.0) { // If mouse active
        let m = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
        // Let's make mouse offset the center
        p -= m;
    }

    // Polar Coords
    let r = length(p);
    var a = atan2(p.y, p.x);

    // Animate rotation
    a += u.config.x * rotSpeed;

    // Repeat Angle
    let segmentAngle = 3.14159 * 2.0 / segments;

    // Mirroring logic
    // We map angle 'a' into [0, segmentAngle]
    // Then reflect if needed

    // Standard fold
    a = a % segmentAngle;
    if (a < 0.0) { a += segmentAngle; } // Handle negative modulo result

    // Triangle fold (mirror half of the segment)
    a = abs(a - segmentAngle * 0.5);

    // Add offset (spiraling)
    // a += r * offsetVal;

    // Convert back to cartesian
    // We have 'a' (which is now folded) and 'r'.
    // We map this back to UV space.

    // We can sample a texture by reconstructing the vector
    var uv_new = vec2<f32>(cos(a), sin(a)) * r;

    // Add spiraling offset here?
    uv_new += vec2<f32>(offsetVal * 0.1);

    // Apply zoom
    uv_new *= zoom;

    // Un-correct aspect and un-center
    uv_new.x /= aspect;
    uv_new += 0.5;

    // Sample
    // Use mirrored repeat for out of bounds?
    // The sampler is 'repeat' by default usually (u_sampler).
    // But let's verify. Renderer says 'addressModeU: repeat'. Good.

    let color = textureSampleLevel(readTexture, u_sampler, uv_new, 0.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
