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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown/Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let beamSize = mix(0.01, 0.15, u.zoom_params.x);
    let burnSpeed = u.zoom_params.y * 0.2;
    // Heal Rate: 0.0 = Permanent (factor 1.0), 1.0 = Fast Heal (factor 0.9)
    let healFactor = mix(1.0, 0.9, u.zoom_params.z);
    let heatMix = u.zoom_params.w;

    // Read Previous State
    // R = Char (0-1), G = Heat (0-1)
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var charLevel = prev.r;
    var heatLevel = prev.g;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    let aspect = resolution.x / resolution.y;
    var dVec = uv - mouse;
    dVec.x *= aspect;
    let dist = length(dVec);

    if (mouseDown && dist < beamSize) {
        // Soft edge brush
        let intensity = smoothstep(beamSize, beamSize * 0.5, dist);
        heatLevel += intensity * burnSpeed;
    }

    // Physics Simulation
    // Heat cools down rapidly
    let cooledHeat = heatLevel * 0.9;

    // Heat converts to Char (burning the material)
    charLevel += cooledHeat * 0.1;
    charLevel = clamp(charLevel, 0.0, 1.0);

    // Char heals over time (if configured)
    charLevel *= healFactor;

    // Render
    let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Visuals
    // Darken by Char
    var finalColor = source.rgb * (1.0 - charLevel);

    // Add glowing heat (Ember effect)
    let fireColor = vec3<f32>(1.0, 0.6, 0.2);
    // Heat glow visibility controlled by param w and heat level
    finalColor += fireColor * cooledHeat * (0.5 + heatMix * 2.0);

    // Save State to dataTextureA (Binding 7)
    // R=Char, G=Heat
    textureStore(dataTextureA, global_id.xy, vec4<f32>(charLevel, cooledHeat, 0.0, 1.0));

    // Output to Screen
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
