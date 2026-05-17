// ═══════════════════════════════════════════════════════════════════
//  Luma Topography
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    // Parameters — bass boosts light intensity
    let heightScale = u.zoom_params.x * 20.0 + 1.0;
    let lightIntensity = u.zoom_params.y * 2.0 * (1.0 + bass * 0.4);
    let shininess = u.zoom_params.z * 32.0 + 1.0;
    let ambient = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 0.001);

    let colorSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let color = colorSample.rgb;
    let luma = getLuma(color);

    let texelSize = 1.0 / resolution;

    let lumaRight = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb);
    let lumaTop   = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb);

    let dX = lumaRight - luma;
    let dY = lumaTop - luma;

    let normal = normalize(vec3<f32>(-dX * heightScale, -dY * heightScale, 1.0));

    let lightHeight = 0.2;
    let pixelPos3D = vec3<f32>(uv.x * aspect, uv.y, luma * 0.2);
    let lightPos3D = vec3<f32>(mousePos.x * aspect, mousePos.y, lightHeight);

    let L = normalize(lightPos3D - pixelPos3D);
    let V = vec3<f32>(0.0, 0.0, 1.0);

    let diff = max(dot(normal, L), 0.0);
    let H = normalize(L + V);
    let spec = pow(max(dot(normal, H), 0.0), shininess);

    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mousePos.x * aspect, mousePos.y));
    let atten = 1.0 / (1.0 + dist * 5.0);

    // Mids add warm shimmer to specular
    let lightColor = vec3<f32>(1.0, 0.95 + mids * 0.05, 0.8);

    let finalDiffuse  = diff * lightColor * lightIntensity * atten;
    let finalSpecular = spec * lightColor * lightIntensity * atten;

    let litColor = clamp(color * (vec3<f32>(ambient) + finalDiffuse) + finalSpecular, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: specular highlight + diffuse strength + original alpha
    let alpha = clamp(spec * atten * 0.6 + diff * atten * 0.3 + colorSample.a * 0.15 + bass * 0.05, 0.0, 1.0);
    let fc = vec4<f32>(litColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
