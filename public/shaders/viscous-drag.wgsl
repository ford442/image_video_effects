// ═══════════════════════════════════════════════════════════════
//  Viscous Drag
//  Simulates dragging through a thick liquid.
//  Uses a velocity/offset field stored in dataTextureA.
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
  zoom_params: vec4<f32>,  // x=Viscosity, y=DragStrength, z=RecoverySpeed, w=DistortionScale
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let viscosity = mix(0.1, 0.9, u.zoom_params.x); // High viscosity = spreads slowly
    let dragStrength = mix(0.1, 2.0, u.zoom_params.y);
    let recovery = mix(0.9, 0.995, u.zoom_params.z); // High = slow recovery
    let scale = mix(0.01, 0.2, u.zoom_params.w);

    // Read previous offset state from history (dataTextureC)
    // We store offset in RG channels
    let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevOffset = prevData.xy;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w; // 1.0 if down

    // To properly "drag", we really need delta mouse...
    // But since we don't have it easily per pixel without extra buffer trickery,
    // we'll simulate a "push" away from mouse, or a "pull" towards.
    // Let's do a "smear" where pixels move towards the mouse if it's close?
    // Actually, "dragging" usually implies moving WITH the mouse.

    // Alternative: Just repel/attract based on distance.
    // Let's do a "finger drag" simulation where the mouse acts as a point of high pressure.

    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uv_aspect, mouse_aspect);
    let radius = 0.15;

    var force = vec2<f32>(0.0);

    // If mouse is present (y > 0 generally implies it's on canvas, but let's check input)
    // Assuming zoom_config.y is valid.

    if (dist < radius && dist > 0.001) {
        // Calculate a vector. Let's make it a swirl or a push.
        // A push away from mouse center:
        let dir = normalize(uv_aspect - mouse_aspect);
        let strength = (1.0 - dist / radius) * dragStrength;

        // If mouse is down, pull in? Or push out?
        // Let's say: Push out by default (displacement).
        force = dir * strength * 0.01;

        // If we wanted to track mouse velocity, we'd need previous mouse pos.
        // But a push-displacement feels like "poking" the liquid.
    }

    // Update offset
    // New Offset = PrevOffset * recovery + force
    // Also diffuse the offset (viscosity) - sample neighbors

    let texel = 1.0 / resolution;
    let up = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).xy;
    let down = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).xy;
    let left = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).xy;
    let right = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).xy;

    let avg = (up + down + left + right) * 0.25;

    // Mix current offset with average neighbor offset based on viscosity
    let diffusedOffset = mix(prevOffset, avg, viscosity);

    let newOffset = diffusedOffset * recovery + force;

    // Clamp offset to avoid crazy artifacts
    newOffset = clamp(newOffset, vec2<f32>(-0.5), vec2<f32>(0.5));

    // Write state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newOffset, 0.0, 1.0));

    // Render
    // Sample readTexture at uv - newOffset * scale
    let sampleUV = uv - newOffset * scale;
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Add specular highlight based on offset gradient (fake normal)
    let normal = normalize(vec3<f32>(newOffset.x, newOffset.y, 0.01));
    let lightDir = normalize(vec3<f32>(0.5, 0.5, 1.0));
    let specular = pow(max(dot(normal, lightDir), 0.0), 20.0) * length(newOffset) * 2.0;

    let finalColor = color + vec4<f32>(specular);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
}
