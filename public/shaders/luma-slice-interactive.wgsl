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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Intensity, y=SliceDensity, z=RGBShift, w=Phase
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;

    // Params
    let intensity = u.zoom_params.x * 0.5; // Max 0.5 screen width displacement
    let sliceCount = 10.0 + u.zoom_params.y * 190.0; // 10 to 200 slices
    let rgbShift = u.zoom_params.z * 0.05;
    let phase = u.zoom_params.w;

    // Slice Calculation
    let sliceHeight = 1.0 / sliceCount;
    let sliceIndex = floor(uv.y * sliceCount);
    let sliceCenterY = (sliceIndex + 0.5) * sliceHeight;

    // Sample trigger point (x determined by mouse X, y by slice center)
    // Adding time to sample X to make it animated if mouse is still
    let sampleX = fract(mouse.x + u.config.x * 0.1);
    let sampleUV = vec2<f32>(sampleX, sliceCenterY);

    let triggerVal = textureSampleLevel(readTexture, non_filtering_sampler, sampleUV, 0.0);

    // Use luminance of the trigger point to determine offset
    let luma = dot(triggerVal.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Offset calculation
    // Modulate by mouse Y distance to center (optional, or just use mouse Y as multiplier)
    let mouseFactor = smoothstep(0.0, 1.0, abs(mouse.y - 0.5) * 2.0 + 0.2);

    let offsetBase = (luma - 0.5 + sin(u.config.x * 2.0 + sliceIndex * phase) * 0.2) * intensity * mouseFactor;

    // RGB Split Sampling
    let uvR = vec2<f32>(uv.x + offsetBase + rgbShift, uv.y);
    let uvG = vec2<f32>(uv.x + offsetBase, uv.y);
    let uvB = vec2<f32>(uv.x + offsetBase - rgbShift, uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Add scanline darkening
    // Distance from slice center
    let distCenter = abs(uv.y - sliceCenterY) / sliceHeight * 2.0; // 0 to 1
    let scanline = 1.0 - smoothstep(0.8, 1.0, distCenter) * 0.3;

    let finalColor = vec3<f32>(r, g, b) * scanline;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
