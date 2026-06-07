// ═══════════════════════════════════════════════════════════════════
//  Dynamic Tessellation (Ornate Fractal Tiles)
//  Category: generative
//  Features: audio-reactive, fractal, tiled, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-06
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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
    return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                     1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                     0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
    let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
    let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
    let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
    return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                    -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                    -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}
fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    let r = select(clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0), 1.0, t <= 66.0);
    let g = select(clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0),
                   clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0), t <= 66.0);
    let b = select(select(clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0), 0.0, t <= 19.0), 1.0, t >= 66.0);
    return vec3<f32>(r, g, b);
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, max_lum / max(l, 1e-4));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let aspect = f32(res.x) / f32(res.y);
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    p += u.zoom_config.yz;
    let density = max(1.0, 5.0 + u.zoom_params.y * 5.0);
    let tile_uv = p * density;
    let tile_id = floor(tile_uv);
    var tile_local = fract(tile_uv) * 2.0 - 1.0;
    var z = tile_local;
    let base_c = vec2<f32>(
        sin(tile_id.x * 0.1 + u.config.x * 0.5),
        cos(tile_id.y * 0.1 + u.config.x * 0.5)
    );

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let iter = i32(max(5.0, 10.0 + u.zoom_params.x * 10.0 + bass * 5.0));
    var n = 0;
    var alive = true;
    for (var i = 0; i < 20; i = i + 1) {
        let stepActive = alive && (i < iter);
        let z_next = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + base_c;
        z = select(z, z_next, stepActive);
        alive = stepActive && (length(z) <= 4.0);
        n = n + select(0, 1, alive);
    }

    let f_val = f32(n) / max(f32(iter), 1.0);
    let temp = mix(2500.0, 8000.0, clamp(bass + 0.5 * sin(u.config.x * 0.3), 0.0, 1.0));
    let warm = blackbodyRGB(temp);
    let cool = blackbodyRGB(temp * 0.35);
    let col = mixOkLab(cool, warm, f_val) * (1.0 + f_val * f_val * 2.5);
    let hdr = hue_preserve_clamp(col, 4.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 2.0;
    let a = clamp(bloomWeight + mids * 0.1 + treble * 0.05, 0.0, 1.0);
    let tm = acesToneMap(hdr) + vec3<f32>((ign(vec2<f32>(coords)) - 0.5) / 255.0);
    let srgb = pow(tm, vec3<f32>(1.0 / 2.2));

    var finalColor = vec4<f32>(srgb * a, a);
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    finalColor = vec4<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5, finalColor.a);

    textureStore(writeTexture, coords, applyGenerativePrimaryControls(finalColor));
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
