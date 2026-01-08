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

// Luma Glass
// P1: Refraction Strength (Depth of glass)
// P2: Smoothness (Blur of normals)
// P3: Specular Sharpness
// P4: Light Height (Imitates light distance)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let strength = u.zoom_params.x * 0.1; // Refraction scale
    let smoothness = 1.0 + u.zoom_params.y * 2.0; // Kernel spacing
    let specularPower = mix(10.0, 100.0, u.zoom_params.z);
    let lightHeight = u.zoom_params.w + 0.1;

    // Calculate Luma Gradient (Pseudo-Normal)
    let step = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y) * smoothness;

    // Sobel-ish sampling
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -step.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, step.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, 0.0), 0.0).rgb;

    let lumT = dot(t, vec3<f32>(0.333));
    let lumB = dot(b, vec3<f32>(0.333));
    let lumL = dot(l, vec3<f32>(0.333));
    let lumR = dot(r, vec3<f32>(0.333));

    // Normal vector from height map (luma)
    // dx = Right - Left, dy = Bottom - Top
    let dX = (lumR - lumL) * strength * 10.0;
    let dY = (lumB - lumT) * strength * 10.0;

    // Surface Normal (approximate)
    let normal = normalize(vec3<f32>(-dX, -dY, 1.0));

    // Light Vector (Mouse is light source)
    let pixelPos = vec3<f32>(uv.x * aspect, uv.y, 0.0);
    let lightPos = vec3<f32>(mouse.x * aspect, mouse.y, lightHeight);
    let lightDir = normalize(lightPos - pixelPos);

    // Refraction:
    // We want to sample the texture at a displaced UV based on the normal.
    // If normal tilts right, we see pixels from the left?
    // Snells law is complex, let's approximate:
    // Offset = Normal.xy * RefractionIndex
    let refractOffset = normal.xy * strength;

    let finalUV = uv + refractOffset;
    let baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Specular Highlight (Phong)
    // View dir is roughly straight down (0,0,1)
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let halfDir = normalize(lightDir + viewDir);
    let specAngle = max(dot(normal, halfDir), 0.0);
    let specular = pow(specAngle, specularPower);

    // Mix
    var finalColor = baseColor.rgb + vec3<f32>(specular);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
}
