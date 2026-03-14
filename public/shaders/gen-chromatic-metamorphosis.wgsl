// ─────────────────────────────────────────────────────────────────────────────
//  Chromatic Metamorphosis
//  Category: GENERATIVE
//  Complexity: VERY HIGH
//  Visual concept: Metaballs morph continuously between sphere, torus, cube,
//    and asymmetric shapes. Color evolves independently from geometry, sliding
//    across surfaces in waves. Beauty in perpetual transformation.
//  Mathematical approach: Smooth-min SDF blending of sphere/torus/box SDFs;
//    time-driven interpolation weights; surface color is a function of normal
//    direction + UV-like projection independent of geometry; ray marching with
//    soft shadows and ambient occlusion.
// ─────────────────────────────────────────────────────────────────────────────
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
    config:      vec4<f32>, // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=unused, y=MouseX, z=MouseY, w=unused
    zoom_params: vec4<f32>, // x=MorphSpeed, y=ColorSpeed, z=BlendRadius, w=LightIntensity
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  HSV → RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s; let h6 = fract(h) * 6.0;
    let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if      (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + (v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  SDFs
// ─────────────────────────────────────────────────────────────────────────────
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth min (k controls blend radius)
// ─────────────────────────────────────────────────────────────────────────────
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ─────────────────────────────────────────────────────────────────────────────
//  3-D rotation helpers
// ─────────────────────────────────────────────────────────────────────────────
fn rotY(p: vec3<f32>, a: f32) -> vec3<f32> {
    let s = sin(a); let c = cos(a);
    return vec3<f32>(c*p.x + s*p.z, p.y, -s*p.x + c*p.z);
}
fn rotX(p: vec3<f32>, a: f32) -> vec3<f32> {
    let s = sin(a); let c = cos(a);
    return vec3<f32>(p.x, c*p.y - s*p.z, s*p.y + c*p.z);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Morphing SDF: blend between 4 shapes by time-driven weights
// ─────────────────────────────────────────────────────────────────────────────
fn sceneSDF(p_in: vec3<f32>, t: f32, blendK: f32, morphT: f32) -> f32 {
    let p = rotX(rotY(p_in, t * 0.17), t * 0.13);

    // Phase: 0=sphere, 1=torus, 2=box, 3=capsule, cycles smoothly
    let phase = fract(morphT * 0.25) * 4.0;
    let w0 = smoothstep(0.0, 1.0, 1.0 - abs(phase - 0.0)) + smoothstep(0.0, 1.0, 1.0 - abs(phase - 4.0));
    let w1 = smoothstep(0.0, 1.0, 1.0 - abs(phase - 1.0));
    let w2 = smoothstep(0.0, 1.0, 1.0 - abs(phase - 2.0));
    let w3 = smoothstep(0.0, 1.0, 1.0 - abs(phase - 3.0));

    let s0 = sdSphere(p, 0.75);
    let s1 = sdTorus(p, vec2<f32>(0.55, 0.22));
    let s2 = sdBox(p, vec3<f32>(0.52, 0.52, 0.52));
    let s3 = sdCapsule(p, vec3<f32>(0.0, -0.45, 0.0), vec3<f32>(0.0, 0.45, 0.0), 0.32);

    // Weighted SDF interpolation via smin chain
    var d = s0 * w0;
    d = smin(d, s1, blendK * w1 + 0.01);
    d = smin(d, s2, blendK * w2 + 0.01);
    d = smin(d, s3, blendK * w3 + 0.01);
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Estimate normal
// ─────────────────────────────────────────────────────────────────────────────
fn sceneNormal(p: vec3<f32>, t: f32, bk: f32, mt: f32) -> vec3<f32> {
    let e = 0.002;
    return normalize(vec3<f32>(
        sceneSDF(p + vec3<f32>(e,0,0), t, bk, mt) - sceneSDF(p - vec3<f32>(e,0,0), t, bk, mt),
        sceneSDF(p + vec3<f32>(0,e,0), t, bk, mt) - sceneSDF(p - vec3<f32>(0,e,0), t, bk, mt),
        sceneSDF(p + vec3<f32>(0,0,e), t, bk, mt) - sceneSDF(p - vec3<f32>(0,0,e), t, bk, mt)
    ));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth noise for material texture
// ─────────────────────────────────────────────────────────────────────────────
fn h2_cm(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn vnoise_cm(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f*f*(3.0-2.0*f);
    return mix(mix(h2_cm(i),h2_cm(i+vec2<f32>(1,0)),u.x),mix(h2_cm(i+vec2<f32>(0,1)),h2_cm(i+vec2<f32>(1,1)),u.x),u.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fresnel reflectance approximation (Schlick)
// ─────────────────────────────────────────────────────────────────────────────
fn fresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  GGX distribution for specular (for iridescent sheen)
// ─────────────────────────────────────────────────────────────────────────────
fn ggxD(NdotH: f32, roughness: f32) -> f32 {
    let a  = roughness * roughness;
    let a2 = a * a;
    let d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (3.14159 * d * d + 1e-6);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ambient occlusion from marching
// ─────────────────────────────────────────────────────────────────────────────
fn ambientOcclusion(p: vec3<f32>, N: vec3<f32>, t: f32, bk: f32, mt: f32) -> f32 {
    var occ = 0.0;
    var scale = 1.0;
    for (var i = 1; i <= 5; i++) {
        let d = 0.02 * f32(i);
        let q = p + N * d;
        let dist = sceneSDF(q, t, bk, mt);
        occ += (d - dist) * scale;
        scale *= 0.5;
    }
    return clamp(1.0 - occ * 3.0, 0.0, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    let uv    = (vec2<f32>(gid.xy) - res * 0.5) / min(res.x, res.y);
    let t     = u.config.x;
    let mouse = u.zoom_config.yz;

    let morphSpeed  = u.zoom_params.x * 0.4 + 0.05;
    let colorSpeed  = u.zoom_params.y * 0.6 + 0.1;
    let blendRadius = u.zoom_params.z * 0.4 + 0.05;
    let lightInt    = u.zoom_params.w * 2.0 + 0.5;

    let morphT = t * morphSpeed;

    // Camera
    let camPos = vec3<f32>(
        sin(t * 0.08 + mouse.x * 3.14) * 2.2,
        cos(t * 0.06 + mouse.y * 1.5) * 0.8,
        cos(t * 0.08 + mouse.x * 3.14) * 2.2
    );
    let target = vec3<f32>(0.0, 0.0, 0.0);
    let fwd    = normalize(target - camPos);
    let right  = normalize(cross(fwd, vec3<f32>(0.0, 1.0, 0.0)));
    let up     = cross(right, fwd);

    let rd = normalize(fwd + uv.x * right + uv.y * up);
    var ro = camPos;

    // Ray march
    var tRay = 0.01;
    var hit  = false;
    var hitP = vec3<f32>(0.0);
    for (var i = 0; i < 80; i++) {
        let p  = ro + rd * tRay;
        let d  = sceneSDF(p, t, blendRadius, morphT);
        if (d < 0.001) { hit = true; hitP = p; break; }
        if (tRay > 8.0) { break; }
        tRay += d * 0.9;
    }

    var col = vec3<f32>(0.02, 0.02, 0.06); // background

    if (hit) {
        let N = sceneNormal(hitP, t, blendRadius, morphT);

        // Independent color field: based on normal + time, not geometry phase
        let colorPhase = dot(N, vec3<f32>(0.577)) * 2.0 + t * colorSpeed;
        let hue = fract(colorPhase * 0.5 + 0.15);
        let sat = 0.6 + 0.4 * abs(sin(colorPhase * 1.7));
        let surfCol = hsv2rgb(hue, sat, 1.0);

        // Lighting
        let lightDir = normalize(vec3<f32>(sin(t * 0.2), 0.7, cos(t * 0.2)));
        let diff = max(dot(N, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, N), -rd), 0.0), 32.0);
        let rim  = pow(1.0 - max(dot(N, -rd), 0.0), 3.0);

        // AO approximation
        let ao = 1.0 - smoothstep(0.0, 0.3, abs(sceneSDF(hitP + N * 0.08, t, blendRadius, morphT)));

        col = surfCol * (0.1 + diff * 0.7 * lightInt) * ao
            + vec3<f32>(1.0) * spec * 0.4
            + surfCol * rim * 0.3;
        col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    }

    if (hit) {
        let N2 = sceneNormal(hitP, t, blendRadius, morphT);

        // ── Fresnel rim light ──────────────────────────────────────────────
        let NdotV = max(dot(N2, -rd), 0.0);
        let fresnelW = fresnel(NdotV, 0.04);
        let rimHue = fract(t * 0.07 + 0.6);
        col += hsv2rgb(rimHue, 1.0, 1.0) * fresnelW * 0.4;

        // ── Material noise texture ─────────────────────────────────────────
        let matNoise = vnoise_cm(hitP.xy * 4.0 + hitP.z * vec2<f32>(1.3, 0.7));
        col = mix(col, col * (0.7 + matNoise * 0.6), 0.3);

        // ── GGX specular sheen ────────────────────────────────────────────
        let halfV = normalize(normalize(vec3<f32>(sin(t*0.2), 0.7, cos(t*0.2))) + (-rd));
        let NdotH = max(dot(N2, halfV), 0.0);
        let roughness = 0.3 + matNoise * 0.4;
        let ggxSpec = ggxD(NdotH, roughness) * 0.15;
        col += hsv2rgb(fract(t * colorSpeed * 0.3 + 0.3), 0.7, 1.0) * ggxSpec;

        // ── Full AO pass ───────────────────────────────────────────────────
        let ao2 = ambientOcclusion(hitP, N2, t, blendRadius, morphT);
        col *= ao2;

        col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    }

    // Depth
    let depthVal = select(0.0, 1.0 - tRay / 8.0, hit);
    textureStore(writeTexture, gid.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthVal, 0.0, 0.0, 1.0));
}
