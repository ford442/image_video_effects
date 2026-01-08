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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Aero Chromatics
// P1: Wind Speed / Force
// P2: Decay Rate (Tail length)
// P3: Chromatic Split (Aberration amount)
// P4: Source Mix (How much new video is injected vs history)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let windStrength = mix(0.5, 5.0, u.zoom_params.x);
    let decay = mix(0.8, 0.995, u.zoom_params.y);
    let chromaSplit = u.zoom_params.z * 0.02; // Small offset
    let sourceMix = mix(0.01, 0.2, u.zoom_params.w);

    // Calculate drag based on current image luma
    // Lighter pixels = lighter weight = move faster (or vice versa?)
    // Let's say Light = Smoke = Fast. Dark = Heavy = Slow.
    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(currentFrame.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let drag = 1.0 - (luma * 0.8); // 0.2 to 1.0

    // Wind Vector
    // Base wind flows diagonally or follows mouse?
    // Let's make wind blow AWAY from mouse.
    let dVec = uv - mouse;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Mouse influence falls off
    let mouseInfluence = smoothstep(0.5, 0.0, dist);

    // Combine base drift with mouse wind
    // Base drift (upwards slightly like smoke)
    let baseWind = vec2<f32>(0.0, -0.001);
    let mouseWind = normalize(dVec) * 0.01 * mouseInfluence * windStrength;

    // Final velocity for this pixel
    // If luma is high, it moves more.
    let velocity = (baseWind + mouseWind) * (luma * 2.0);

    // To simulate advection, we sample FROM (uv - velocity)
    // Because the smoke at (uv) came from (uv - velocity).

    // Chromatic Advection: Sample R, G, B from slightly different locations
    let offsetR = velocity * (1.0 + chromaSplit);
    let offsetG = velocity;
    let offsetB = velocity * (1.0 - chromaSplit);

    let prevR = textureSampleLevel(dataTextureC, u_sampler, uv - offsetR, 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, uv - offsetG, 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, uv - offsetB, 0.0).b;
    let prevAlpha = textureSampleLevel(dataTextureC, u_sampler, uv - velocity, 0.0).a; // Carry alpha

    let historyColor = vec3<f32>(prevR, prevG, prevB);

    // Mix new source
    // If it's bright, we inject more source (smoke generation).
    // If dark, we inject less (transparent).
    let injectAmount = sourceMix * luma;

    var finalColor = mix(historyColor * decay, currentFrame.rgb, injectAmount);

    // Clamp
    finalColor = max(vec3<f32>(0.0), finalColor);

    // Store to history (A) and Display (Write)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
}
