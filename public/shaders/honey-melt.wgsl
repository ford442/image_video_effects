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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Scale, y=Radius, z=Distort, w=Softness
  ripples: array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    let mousePos = u.zoom_config.yz;

    // Params
    let gridSize = mix(10.0, 80.0, u.zoom_params.x);
    let meltRadius = u.zoom_params.y * 0.5;
    let distortStr = u.zoom_params.z;
    let softness = u.zoom_params.w;
    let time = u.config.x;

    // --- Hex Grid Logic ---
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let uvScaled = uv * aspectVec * gridSize;
    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);
    let centerA = idA * r;
    let centerB = idB * r + h;
    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);
    let center = select(centerB, centerA, distA < distB);
    let localVec = uvScaled - center;

    // Grid UV (Center of hex)
    // Map back to 0-1
    let gridUV = center / gridSize / aspectVec;

    // --- Melt Interaction ---
    let centerScreen = gridUV * aspectVec;
    let mouseScreen = mousePos * aspectVec;
    let distToMouse = distance(centerScreen, mouseScreen);

    // Melt Factor: 1.0 = Fully Melted (Near mouse), 0.0 = Solid (Far)
    let melt = 1.0 - smoothstep(meltRadius, meltRadius + softness + 0.01, distToMouse);

    // --- Rendering ---

    // 1. Solid State: Distorted UV inside hex to look like a lens/honey drop
    // Bulge effect
    let len = length(localVec);
    let bulge = localVec * (1.0 - len * 0.8); // Simple bulge
    let solidUV = (center + bulge) / gridSize / aspectVec;

    // Add a golden rim/highlight for honeycomb look
    let rim = smoothstep(0.4, 0.5, len); // Darken edges

    // 2. Melted State: Fluid distortion
    let noiseVal = noise(uv * 10.0 + time * 0.5);
    let fluidUV = uv + vec2<f32>(noiseVal, -noiseVal) * 0.05 * distortStr;

    // Mix UVs? Or Mix Colors?
    // Mixing UVs can cause artifacts if they are far apart.
    // Let's Mix Colors.

    var colSolid = textureSampleLevel(readTexture, u_sampler, solidUV, 0.0);
    // Tint solid state like honey
    colSolid = mix(colSolid, vec4<f32>(1.0, 0.8, 0.2, 1.0), 0.2); // Golden tint
    colSolid = mix(colSolid, vec4<f32>(0.2, 0.1, 0.0, 1.0), rim * 0.8); // Dark borders

    let colFluid = textureSampleLevel(readTexture, u_sampler, fluidUV, 0.0);

    // Final Mix
    let finalColor = mix(colSolid, colFluid, melt);

    textureStore(writeTexture, global_id.xy, finalColor);
}
