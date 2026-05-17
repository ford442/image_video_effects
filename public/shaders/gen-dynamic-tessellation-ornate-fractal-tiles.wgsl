// ═══════════════════════════════════════════════════════════════════
//  Dynamic Tessellation (Ornate Fractal Tiles)
//  Category: generative
//  Features: audio-reactive, fractal, tiled
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Pixelocity Upgrade Swarm — Phase A
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

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
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (t <= 66.0) { r = 1.0; }
    else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
    if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
    else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
    if (t >= 66.0) { b = 1.0; }
    else if (t <= 19.0) { b = 0.0; }
    else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
    return vec3<f32>(r, g, b);
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, max_lum / max(l, 1e-4));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = textureDimensions(writeTexture);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }
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
    let bass = plasmaBuffer[0].x;
    let iter = i32(max(5.0, 10.0 + u.zoom_params.x * 10.0 + bass * 5.0));
    var n = 0;
    for (var i = 0; i < 20; i++) {
        if (i >= iter) { break; }
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + base_c;
        if (length(z) > 4.0) { break; }
        n++;
    }
    let f_val = f32(n) / max(f32(iter), 1.0);
    let temp = mix(2500.0, 8000.0, clamp(bass + 0.5 * sin(u.config.x * 0.3), 0.0, 1.0));
    let warm = blackbodyRGB(temp);
    let cool = blackbodyRGB(temp * 0.35);
    let col = mixOkLab(cool, warm, f_val) * (1.0 + f_val * f_val * 2.5);
    let hdr = hue_preserve_clamp(col, 4.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    let data_alpha = clamp(0.3 + f_val * 0.7, 0.0, 1.0);
    textureStore(dataTextureA, coords, vec4<f32>(tile_id, f_val, data_alpha));
    let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 2.0;
    let a = clamp(bloomWeight, 0.0, 1.0);
    let tm = aces(hdr) + vec3<f32>((ign(vec2<f32>(coords)) - 0.5) / 255.0);
    let srgb = pow(tm, vec3<f32>(1.0 / 2.2));
    textureStore(writeTexture, coords, vec4<f32>(srgb * a, a));
}
