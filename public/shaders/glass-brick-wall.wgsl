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
  zoom_params: vec4<f32>,  // x=BrickSize, y=DistortionStr, z=MortarSize, w=SpecularStr
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let brickSize = mix(10.0, 50.0, u.zoom_params.x); // x: Brick Density
    let distortionStr = mix(0.0, 0.1, u.zoom_params.y); // y: Refraction strength
    let mortarSize = mix(0.01, 0.1, u.zoom_params.z); // z: Mortar thickness
    let specStr = mix(0.0, 2.0, u.zoom_params.w); // w: Specular strength

    // Mouse as light source
    let mouse = u.zoom_config.yz;
    let lightPos = vec3<f32>(mouse * vec2<f32>(aspect, 1.0), 0.5);
    let pixelPos = vec3<f32>(uv * vec2<f32>(aspect, 1.0), 0.0);
    let lightDir = normalize(lightPos - pixelPos);

    // Grid Logic
    let gridUV = uv * vec2<f32>(brickSize * aspect, brickSize);
    let cellID = floor(gridUV);
    let cellUV = fract(gridUV); // 0.0 to 1.0

    // Squircle Distance Field for Height/Normal
    // Center is 0.5, 0.5
    let d = cellUV - 0.5;
    // Radial falloff for "pillow" shape
    let r = dot(d, d) * 4.0; // 0 at center, approx 1 at corners

    // Calculate Normal from height map
    // Height h = 1.0 - r^2 (roughly)
    // Normal ~ (-dh/dx, -dh/dy, 1)
    // dh/dx = -2*x, dh/dy = -2*y
    // So normal xy is proportional to d

    let normalXY = d * -2.0;
    let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
    let normal = normalize(vec3<f32>(normalXY, normalZ));

    // Mortar Mask
    // distance from edge
    let distFromCenter = max(abs(d.x), abs(d.y));
    let mortarMask = smoothstep(0.48 - mortarSize, 0.5, distFromCenter);

    // Distortion
    // If in mortar, no distortion (or simple offset). If in brick, refract.
    let refractOffset = normal.xy * distortionStr * (1.0 - mortarMask);

    // Sample texture with refraction
    let finalUV = uv + refractOffset;
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Specular Highlight (Phong)
    let viewDir = vec3<f32>(0.0, 0.0, 1.0); // Viewer is straight on
    let halfDir = normalize(lightDir + viewDir);
    let specular = pow(max(dot(normal, halfDir), 0.0), 16.0) * specStr;

    // Add specular to brick only
    color = color + vec4<f32>(specular) * (1.0 - mortarMask);

    // Darken Mortar
    color = mix(color, vec4<f32>(0.1, 0.1, 0.1, 1.0), mortarMask);

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
