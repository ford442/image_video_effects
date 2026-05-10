// ═══════════════════════════════════════════════════════════════════
//  Fluid Vortex – Pass 2: Distortion Rendering
//  Category: distortion
//  Features: multi-pass-2, motion-blur, iridescent vorticity, palette grading
//  Inputs: dataTextureC (velocity field from Pass 1), readTexture
//  Outputs: writeTexture (final RGBA), writeDepthTexture
//  Phase B / Visualist
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

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=VortexStrength, y=MotionBlurAmt, z=Iridescence, w=PaletteMix
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let vortexStrength = u.zoom_params.x;
    let blurAmt        = clamp(u.zoom_params.y, 0.0, 1.0);
    let iridescence    = clamp(u.zoom_params.z, 0.0, 1.0);
    let paletteMix     = clamp(u.zoom_params.w, 0.0, 1.0);

    let field = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let velocity  = field.rg;
    let vorticity = field.b;
    let velMag    = field.a;

    let displacementScale = mix(0.02, 0.18, vortexStrength) * (1.0 + bass * 0.3);
    let displacedUV = uv + velocity * displacementScale;

    // Swirl (curl-augmented displacement) via perpendicular rotation
    let swirlStrength = vorticity * 0.012 * vortexStrength;
    let toCenter = uv - vec2<f32>(0.5);
    let swirlRot = vec2<f32>(-toCenter.y, toCenter.x) * swirlStrength;
    let baseUV = displacedUV + swirlRot;

    // Multi-tap motion blur along the velocity vector — 5 taps with golden-ratio spacing
    var accum = vec3<f32>(0.0);
    var wsum = 0.0;
    let blurStep = velocity * 0.012 * blurAmt * (1.0 + bass * 0.3);
    for (var i = -2; i <= 2; i++) {
        let t = f32(i) * 0.5;
        let w = exp(-t * t);
        let s = textureSampleLevel(readTexture, u_sampler, fract(baseUV + blurStep * t), 0.0).rgb;
        accum += s * w;
        wsum += w;
    }
    var warpedColor = accum / max(wsum, 1e-4);

    // Iridescent vorticity tint — phase wraps with vorticity sign + magnitude
    let phase = vorticity * TAU * 0.5 + time * 0.4;
    let iridTint = vec3<f32>(
        0.5 + 0.5 * cos(phase),
        0.5 + 0.5 * cos(phase + 2.094),
        0.5 + 0.5 * cos(phase + 4.188)
    );
    warpedColor = mix(warpedColor, warpedColor * (0.7 + iridTint * 0.6), iridescence * velMag);

    // Plasma palette grading driven by velocity magnitude
    let palIdx = u32(clamp((velMag * 1.5 + 0.1) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    var finalRGB = mix(warpedColor, warpedColor * (0.6 + palette * 0.7), paletteMix * 0.6);

    // Velocity glow (HDR shoulder)
    let velocityGlow = smoothstep(0.0, 0.5, velMag) * 0.15 * vortexStrength;
    finalRGB = finalRGB * (1.0 + velocityGlow);

    // Bloom-style alpha for high-velocity regions
    let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = max(0.0, luma - 0.7) * 3.0;
    let scatter = (velMag + abs(vorticity) * 0.15) * 0.25 * vortexStrength;
    let finalAlpha = clamp(0.55 + bloom * 0.4 + velMag * 0.25 - scatter, 0.2, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, finalAlpha));

    let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, fract(baseUV), 0.0).r;
    let depthMod = 1.0 + velMag * 0.1 * vortexStrength;
    textureStore(writeDepthTexture, coord, vec4<f32>(depthSample * depthMod, 0.0, 0.0, 0.0));
}
