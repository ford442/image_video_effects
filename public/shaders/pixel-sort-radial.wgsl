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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let stretchAmt = u.zoom_params.x; // How much to stretch pixels
    let threshold = u.zoom_params.y; // Luminance threshold for stretch
    let radius = 0.1 + u.zoom_params.z * 0.8;
    let direction = u.zoom_params.w; // 0.0 = Out, 1.0 = In (Spiral?)

    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));

    // Pixel Sort / Stretch Effect
    // We displace the UV lookup towards the mouse center (or away) based on luminance

    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    var finalUV = uv;

    // Only affect area around mouse
    let influence = smoothstep(radius, 0.0, dist);

    if (influence > 0.001) {
        // If pixel is bright enough, stretch it?
        // Or stretch DARK pixels?
        let stretchFactor = step(threshold, luma) * stretchAmt * influence;

        let dirToMouse = normalize(mousePos - uv);

        // Push away or pull in?
        // If direction < 0.5, push OUT (uv moves towards mouse)
        // If direction > 0.5, pull IN (uv moves away from mouse)

        // Actually, to push pixels OUT, we need to sample CLOSER to the center.
        // So uv -= dirToMouse * amount

        let dir = mix(dirToMouse, -dirToMouse, step(0.5, direction));

        // Add some spiral twist
        let tangent = vec2<f32>(-dir.y, dir.x);
        let twist = tangent * influence * 0.2; // slight twist

        finalUV = uv - (dir * stretchFactor * 0.2) + twist;
    }

    let finalColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
