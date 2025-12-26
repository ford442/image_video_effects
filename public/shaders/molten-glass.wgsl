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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);

    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;

    // Parameters
    let heatRadius = u.zoom_params.x * 0.2; // 0.0 to 0.2
    let viscosity = u.zoom_params.y; // 0.0 to 1.0
    let refraction = u.zoom_params.z * 0.1; // 0.0 to 0.1
    let coolingRate = 0.01 + u.zoom_params.w * 0.1; // 0.01 to 0.11

    // Mouse interaction
    let mousePos = u.zoom_config.yz; // Mouse is 0-1
    // Correct aspect ratio for distance calculation
    let aspect = resolution.x / resolution.y;
    // Mouse UV is already 0-1
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Read previous heat state from history (dataTextureC)
    // History stores: r = heat/distortion strength
    let prevColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var heat = prevColor.r;

    // Decay heat
    heat = max(0.0, heat - coolingRate);

    // Add heat from mouse
    // Smooth falloff
    let influence = smoothstep(heatRadius, 0.0, dist);
    // Add influence to heat (accumulation)
    heat = min(1.0, heat + influence * 0.5);

    // Write new heat state to dataTextureA (history)
    textureStore(dataTextureA, coord, vec4<f32>(heat, 0.0, 0.0, 1.0));

    // Calculate distortion
    // Use heat to drive a sine wave wobble
    let wobble = sin(uv.y * 20.0 + time * 5.0) * cos(uv.x * 20.0 + time * 3.0) * 0.02;
    let distort = (heat * refraction) + (heat * wobble * viscosity);

    // Offset UVs based on heat gradient (simple radial push for now, plus wobble)
    let pushDir = normalize(uv - mousePos);
    // Protect against NaN if uv == mousePos
    let safePushDir = select(pushDir, vec2<f32>(0.0, 0.0), length(uv - mousePos) < 0.001);

    let offset = safePushDir * distort * 0.5 + vec2<f32>(
        sin(uv.y * 50.0 + heat * 10.0),
        cos(uv.x * 50.0 + heat * 10.0)
    ) * distort * 0.5;

    let finalUV = uv + offset;
    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Add some specular highlight where heat is high (glossy/melting look)
    // Edge detection on heat?
    let gloss = smoothstep(0.8, 1.0, heat) * 0.2;

    // Tint slightly red/orange where hot
    let hotColor = vec3<f32>(1.0, 0.5, 0.2);
    let blendedColor = mix(color.rgb, hotColor, heat * 0.1);

    textureStore(writeTexture, coord, vec4<f32>(blendedColor + vec3<f32>(gloss), 1.0));
}
