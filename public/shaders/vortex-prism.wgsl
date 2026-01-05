// ═══════════════════════════════════════════════════════════════════════════════
//  VORTEX PRISM
//  Twisting vortex effect that separates colors prismatically.
// ═══════════════════════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=Width, w=Height
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=TwistAmount, y=PrismStrength, z=Radius, w=Smoothness
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(
        v.x * c - v.y * s,
        v.x * s + v.y * c
    );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;

    // Params
    let twistAmount = (u.zoom_params.x - 0.5) * 20.0; // -10 to 10
    let prismStrength = u.zoom_params.y * 0.1;
    let radius = mix(0.1, 1.5, u.zoom_params.z);
    let smoothness = u.zoom_params.w;

    let mouseX = u.zoom_config.y;
    let mouseY = u.zoom_config.z;
    let isMouseDown = u.zoom_config.w;

    // Center of vortex
    var center = vec2<f32>(mouseX, mouseY);
    if (mouseX == 0.0 && mouseY == 0.0) {
        center = vec2<f32>(0.5, 0.5);
    }

    // Aspect Ratio Correction
    let aspect = resolution.x / resolution.y;

    let fragCoord = vec2<f32>(global_id.xy);
    var uv = fragCoord / resolution;

    // UV relative to center, corrected for aspect
    var d = uv - center;
    d.x = d.x * aspect;

    let dist = length(d);

    // Twist calculation
    // Angle decreases with distance
    let falloff = smoothstep(radius, 0.0, dist);
    let twistAngle = falloff * twistAmount;

    // Prismatic Separation
    // We sample R, G, B at slightly different twist angles

    let angleR = twistAngle * (1.0 - prismStrength);
    let angleG = twistAngle;
    let angleB = twistAngle * (1.0 + prismStrength);

    // Rotate the displacement vector 'd' and add back to center
    // We need to un-correct aspect ratio after rotation

    // Red
    var dR = rotate(d, angleR);
    dR.x = dR.x / aspect;
    let uvR = center + dR;

    // Green
    var dG = rotate(d, angleG);
    dG.x = dG.x / aspect;
    let uvG = center + dG;

    // Blue
    var dB = rotate(d, angleB);
    dB.x = dB.x / aspect;
    let uvB = center + dB;

    // Sample
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Vignette / fade at edge of effect
    // Optionally mix with original coordinate if outside radius

    var color = vec4<f32>(r, g, b, 1.0);

    // Optional: add a slight glow at the center
    if (dist < 0.05 * radius) {
        color = color + vec4<f32>(0.1, 0.1, 0.2, 0.0) * (1.0 - dist / (0.05 * radius));
    }

    textureStore(writeTexture, global_id.xy, color);

    // Depth Pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
