// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Luma Magnetism
// Param1: Magnetic Strength (how much bright pixels are pulled)
// Param2: Effect Radius
// Param3: Falloff (Hardness)
// Param4: Luma Threshold (Only pixels brighter than this are affected)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let strength = u.zoom_params.x; // -1.0 to 1.0 (Attract vs Repel)
    let radius = max(u.zoom_params.y, 0.01);
    let hardness = u.zoom_params.z * 5.0 + 1.0;
    let threshold = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let diff = uv - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));

    // Sample current color to check luminance
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    var sampleOffset = vec2<f32>(0.0);

    // Only affect if luma > threshold
    if (luma > threshold && dist < radius && dist > 0.001) {
        let t = dist / radius;
        let falloff = pow(1.0 - t, hardness);

        // Direction from mouse to UV (push away vector)
        let dir = normalize(diff);

        // To pull pixels IN towards mouse, we must sample OUT away from mouse.
        // So we ADD (UV - Mouse) direction.
        // Strength > 0 = Pull (Magnet). Strength < 0 = Push.
        // Wait, if I add (UV - Mouse) to UV, I get further from mouse.
        // So Sample point is further out.
        // The pixel AT SamplePoint (far) moves TO UV (near).
        // So the image moves IN.

        // Modulation by Luma: Brighter pixels feel more force.
        // We use the luma of the *destination* to decide if we pull.
        // This effectively tears the bright parts away from the dark parts.

        sampleOffset = dir * falloff * strength * luma * 0.2;
    }

    let finalUV = clamp(uv + sampleOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let finalColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    textureStore(writeTexture, global_id.xy, finalColor);
}
