// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=MeltSpeed, y=HeatIntensity, z=Persistence, w=LumaThreshold
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let meltSpeed = u.zoom_params.x;    // e.g. 0.005
    let heatIntensity = u.zoom_params.y;// e.g. 2.0
    let persistence = u.zoom_params.z;  // e.g. 0.95
    let lumaThreshold = u.zoom_params.w;// e.g. 0.5

    // Get current input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = luminance(inputColor.rgb);

    // Calculate base velocity (downwards)
    // Brighter pixels melt faster if luma > threshold
    let meltFactor = max(0.0, luma - lumaThreshold) * 2.0;
    var velocity = vec2<f32>(0.0, meltSpeed * (0.5 + meltFactor));

    // Mouse Interaction (Heat)
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let aspect_uv = vec2<f32>(uv.x * aspect, uv.y);
    let aspect_mouse = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(aspect_uv, aspect_mouse);

    // Heat radius
    let heatRadius = 0.2;
    if (dist < heatRadius) {
        let heat = (1.0 - dist / heatRadius) * heatIntensity;
        // Heat increases downward velocity and adds some outward spread
        let spread = normalize(aspect_uv - aspect_mouse) * 0.01 * heat;
        velocity.y = velocity.y + meltSpeed * heat * 5.0;
        velocity.x = velocity.x + spread.x;
    }

    // Sample previous frame (history) from "upwards" (inverse velocity)
    // We want to fetch what WAS at (uv - velocity) in the previous frame
    let prevUV = uv - velocity;

    // Boundary check for prevUV
    var prevColor = vec4<f32>(0.0);
    if (prevUV.x >= 0.0 && prevUV.x <= 1.0 && prevUV.y >= 0.0 && prevUV.y <= 1.0) {
        prevColor = textureSampleLevel(dataTextureC, non_filtering_sampler, prevUV, 0.0);
    }

    // Mix input and history
    // If persistence is high, the trail stays longer.
    // We want the input to refresh the painting, but the "melt" to drag it down.
    // Standard feedback loop: new = mix(input, prev, blend)

    // But purely mixing makes it look like a ghost trail.
    // We want the pixels to physically move.
    // If we use 'prevColor' as the source of truth for the melting part:

    let result = mix(inputColor, prevColor, persistence);

    // Write to display and history
    textureStore(writeTexture, global_id.xy, result);
    textureStore(dataTextureA, global_id.xy, result);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
