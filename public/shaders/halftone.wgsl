// ═══════════════════════════════════════════════════════════════════
//  Retro Halftone
//  Category: retro-glitch
//  Features: mouse-focus, screen-rotation, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

fn luminance(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }

// ═══ UNIQUE VISUAL IDEA helpers: paper fiber grain ═══
fn paperHash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
fn paperGrain(uv: vec2<f32>) -> f32 {
    // Anisotropic fibre noise — paper has a directional grain from the pulp rollers.
    let p = uv * vec2<f32>(520.0, 180.0);
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let n = mix(mix(paperHash(i), paperHash(i + vec2<f32>(1.0, 0.0)), u.x),
                mix(paperHash(i + vec2<f32>(0.0, 1.0)), paperHash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
    return n;
}

fn ellipDot(uv: vec2<f32>, center: vec2<f32>, radius: f32, axis: vec2<f32>, stretch: f32) -> f32 {
    let d = uv - center;
    let along = dot(d, axis);
    let perp  = vec2<f32>(d.x - along * axis.x, d.y - along * axis.y);
    let dStretched = sqrt((along * along) / max(stretch * stretch, 1e-3) + dot(perp, perp));
    let valid = step(1e-4, radius);
    return valid * smoothstep(radius, max(radius - 0.02, 0.0), dStretched);
}

fn screen_dot(uv: vec2<f32>, scale: f32, angle: f32, sample: vec3<f32>, channelMask: vec3<f32>,
              axis: vec2<f32>, stretch: f32, contrast: f32) -> f32 {
    let c = cos(angle);
    let s = sin(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    let rUV = rot * uv * scale;
    let grid = floor(rUV);
    let cellUv = rUV - grid;
    let density = clamp(dot((1.0 - sample) * channelMask, vec3<f32>(1.0)) * contrast, 0.0, 1.0);
    let radius = density * 0.5;
    return ellipDot(cellUv, vec2<f32>(0.5), radius, axis, stretch);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let dM = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let focus = exp(-dM * dM * 8.0);
    let baseScale = max(mix(6.0, 64.0, clamp(u.zoom_params.x, 0.0, 1.0)), 1.0)
                  * (1.0 + focus * 2.0 + bass * 0.2);

    let velAngle = time * 0.5 + bass * 2.0;
    let velAxis = vec2<f32>(cos(velAngle), sin(velAngle));
    let stretch = mix(1.0, 1.0 + bass * 0.5 + treble * 0.3, focus * 0.7);
    let baseAngle = u.zoom_params.w * PI + bass * 0.4;
    let contrast = mix(0.5, 1.5, clamp(u.zoom_params.y, 0.0, 1.0));

    let sampleColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    let monoDot = screen_dot(uv, baseScale, baseAngle, sampleColor, vec3<f32>(0.299, 0.587, 0.114),
                             velAxis, stretch, contrast);
    let monoPalIdx = u32(clamp(luminance(sampleColor) * 255.0, 0.0, 255.0));
    let bufLen = arrayLength(&plasmaBuffer);
    let monoTint = plasmaBuffer[monoPalIdx % max(1u, bufLen)].rgb;
    let inkTint = mix(vec3<f32>(0.0), monoTint, mouseDown);
    let monoColor = mix(vec3<f32>(1.0), mix(vec3<f32>(0.0), inkTint, mouseDown), monoDot);

    // ═══ UNIQUE VISUAL IDEA: offset-press plate misregistration ═══
    // On a real press each CMYK plate prints in a separate pass; a loose press
    // leaves the plates slightly out of register. We offset each plate's *sampled
    // image* by a tiny, slowly-drifting vector so colours fringe apart like cheap
    // newsprint / risograph. Mouse press tightens registration (a "calibrated" press).
    let regAmt = mix(0.004, 0.0006, mouseDown) * (1.0 + bass * 0.5);
    let regC = vec2<f32>( cos(time * 0.7),        sin(time * 0.7)) * regAmt;
    let regM = vec2<f32>( cos(time * 0.5 + 2.1),  sin(time * 0.5 + 2.1)) * regAmt;
    let regY = vec2<f32>( cos(time * 0.9 + 4.2),  sin(time * 0.9 + 4.2)) * regAmt;
    let sampC = textureSampleLevel(readTexture, u_sampler, clamp(uv + regC, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let sampM = textureSampleLevel(readTexture, u_sampler, clamp(uv + regM, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let sampY = textureSampleLevel(readTexture, u_sampler, clamp(uv + regY, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    let cDot = screen_dot(uv, baseScale, baseAngle + 15.0 * PI / 180.0, sampC, vec3<f32>(1.0, 0.0, 0.0), velAxis, stretch, contrast);
    let mDot = screen_dot(uv, baseScale, baseAngle + 75.0 * PI / 180.0, sampM, vec3<f32>(0.0, 1.0, 0.0), velAxis, stretch, contrast);
    let yDot = screen_dot(uv, baseScale, baseAngle +  0.0 * PI / 180.0, sampY, vec3<f32>(0.0, 0.0, 1.0), velAxis, stretch, contrast);
    let kDot = screen_dot(uv, baseScale * 1.05, baseAngle + 45.0 * PI / 180.0, sampleColor, vec3<f32>(0.299, 0.587, 0.114), velAxis, stretch, contrast);
    let cyan    = vec3<f32>(0.0, 0.7, 0.9);
    let magenta = vec3<f32>(0.9, 0.0, 0.6);
    let yellow  = vec3<f32>(0.95, 0.85, 0.0);
    let black   = vec3<f32>(0.05, 0.05, 0.08);
    var cmykColor = vec3<f32>(1.0);
    cmykColor *= mix(vec3<f32>(1.0), cyan,    cDot);
    cmykColor *= mix(vec3<f32>(1.0), magenta, mDot);
    cmykColor *= mix(vec3<f32>(1.0), yellow,  yDot);
    cmykColor *= mix(vec3<f32>(1.0), black,   kDot);

    let isMono = select(0.0, 1.0, u.zoom_params.z < 0.5);
    var outColor = mix(cmykColor, monoColor, isMono);

    // Paper fibre grain — multiplies the ink so the white paper shows its texture
    // and ink density varies slightly across the sheet (cheap-stock authenticity).
    let grain = paperGrain(uv);
    outColor *= 0.92 + grain * 0.12;

    let coverage = 1.0 - luminance(outColor);
    let alpha = clamp(coverage * 0.85 + focus * 0.15 + 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(outColor, alpha);

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
