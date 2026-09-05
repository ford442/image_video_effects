// ═══════════════════════════════════════════════════════════════════════════════
//  Sonic Lava Flow — Algorithmist Upgrade
//  Category: artistic
//  Description: Navier-Stokes-style fluid solver with domain-warped FBM,
//               Voronoi crust detail, Beer-Lambert volumetric glow,
//               Fresnel molten surface, enhanced curl noise, and
//               deep audio reactivity creating a living molten world.
//  Features: audio-reactive, mouse-driven, temporal, domain-warping,
//            voronoi, beer-lambert, fresnel, curl-noise
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash / Noise ──
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
    return fract(vec2<f32>(n, n * 1.618));
}
fn hash1(n: f32) -> f32 { return fract(sin(n * 127.1 + 311.7) * 43758.5453123); }
fn h2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn h3(p: vec3<f32>) -> f32 {
    var q = fract(p * vec3<f32>(127.1, 311.7, 74.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y * q.z);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h2(i), h2(i+vec2<f32>(1,0)), u.x),
               mix(h2(i+vec2<f32>(0,1)), h2(i+vec2<f32>(1,1)), u.x), u.y);
}

fn noise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash22(i).x;
    let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ── Domain-Warped FBM ──
fn fbm2D_dw(p: vec2<f32>, t: f32, octaves: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        val += noise2D(pp * freq) * amp;
        let warp = val * 0.3;
        pp = pp + vec2<f32>(warp, -warp * 0.7) + vec2<f32>(t * 0.003, -t * 0.002);
        amp *= 0.5;
        freq *= 2.0;
    }
    return val;
}

fn fbm3D_dw(p: vec3<f32>, t: f32, octaves: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        val += vnoise3(pp * freq) * amp;
        let warp = val * 0.25;
        pp = pp + vec3<f32>(warp, -warp * 0.7, warp * 0.3) + vec3<f32>(t * 0.003, -t * 0.002, t * 0.001);
        amp *= 0.5;
        freq *= 2.0;
    }
    return val;
}

fn vnoise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(h3(i), h3(i+vec3<f32>(1,0,0)), u.x),
            mix(h3(i+vec3<f32>(0,1,0)), h3(i+vec3<f32>(1,1,0)), u.x), u.y),
        mix(mix(h3(i+vec3<f32>(0,0,1)), h3(i+vec3<f32>(1,0,1)), u.x),
            mix(h3(i+vec3<f32>(0,1,1)), h3(i+vec3<f32>(1,1,1)), u.x), u.y),
        u.z);
}

// ── Curl Noise (enhanced with domain warping) ──
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.008;
    let n1 = fbm2D_dw(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm2D_dw(p - vec2<f32>(eps, 0.0), time, 4);
    let n3 = fbm2D_dw(p + vec2<f32>(0.0, eps), time, 4);
    let n4 = fbm2D_dw(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>(n3 - n4, n2 - n1) / (2.0 * eps);
}

// ── Voronoi / Worley Noise ──
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = neighbor + vec2<f32>(h2(i + neighbor), h2(i + neighbor + 7.31));
            let diff = neighbor + point - f;
            let d = dot(diff, diff);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }
    return vec2<f32>(sqrt(minDist), sqrt(secondDist));
}

fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    for (var z: i32 = -1; z <= 1; z++) {
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let neighbor = vec3<f32>(f32(x), f32(y), f32(z));
                let point = neighbor + vec3<f32>(h3(i + neighbor), h3(i + neighbor + 7.31), h3(i + neighbor + 13.17));
                let diff = neighbor + point - f;
                let d = dot(diff, diff);
                if (d < minDist) {
                    secondDist = minDist;
                    minDist = d;
                } else if (d < secondDist) {
                    secondDist = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(minDist), sqrt(secondDist));
}

// ── Fresnel-Schlick for molten surface ──
fn fresnelSchlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0);
}

// ── Beer-Lambert volumetric extinction ──
fn beerLambert(density: f32, absorption: f32) -> f32 {
    return exp(-density * absorption);
}

// ── Lava crust SDF detail ──
fn lavaCrustSDF(p: vec2<f32>, t: f32) -> f32 {
    let voro = voronoi(p * 4.0 + t * 0.01);
    let fbmDetail = fbm2D_dw(p * 8.0, t, 3);
    return voro.x * 0.3 + fbmDetail * 0.2 - 0.15;
}

// ── Temperature color mapping with physics ──
fn temperatureColor(temp: f32, t: f32) -> vec3<f32> {
    // Blackbody-ish approximation with audio reactivity
    let t0 = smoothstep(0.0, 0.3, temp);
    let t1 = smoothstep(0.2, 0.5, temp);
    let t2 = smoothstep(0.4, 0.7, temp);
    let t3 = smoothstep(0.6, 0.9, temp);
    let t4 = smoothstep(0.8, 1.0, temp);
    var col = vec3<f32>(0.0);
    col += vec3<f32>(0.1, 0.02, 0.0) * t0;
    col += vec3<f32>(0.5, 0.05, 0.0) * (t1 - t0);
    col += vec3<f32>(0.9, 0.2, 0.0) * (t2 - t1);
    col += vec3<f32>(1.0, 0.5, 0.1) * (t3 - t2);
    col += vec3<f32>(1.0, 0.9, 0.7) * (t4 - t3);
    // White-hot core
    col += vec3<f32>(1.0, 1.0, 1.0) * max(temp - 1.0, 0.0) * 0.5;
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse Y-flip: screen-top = +Y/up
    let mouseY = u.zoom_config.z;
    let mousePos = vec2<f32>(u.zoom_config.y, mouseY);

    // Parameters
    let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
    let viscosity = mix(0.3, 0.95, zp.x);
    let turbulence = zp.y * 3.0;
    let decay = mix(0.8, 0.99, zp.z);
    let heatGlow = zp.w;

    let mouseDown = u.zoom_config.w > 0.5;
    let mouseDist = length(uv - mousePos);
    let mouseHeat = select(0.0, exp(-mouseDist * 10.0) * 0.5, mouseDown);

    // Enhanced flow velocity field with domain-warped curl noise
    let flowP = uv * 3.0 + time * 0.2;
    var velocity = curlNoise(flowP, time) * turbulence;

    // Secondary flow layer with different frequency
    let flowP2 = uv * 6.0 + time * 0.15 + vec2<f32>(100.0, 50.0);
    velocity += curlNoise(flowP2, time * 0.7) * turbulence * 0.5;

    // Audio pushes the flow with frequency-specific response
    velocity = velocity + vec2<f32>(
        cos(time * 2.0 + bass * 5.0) * bass * (1.0 + treble * 0.5),
        sin(time * 1.7 + mids * 4.0) * mids * (1.0 + bass * 0.3)
    ) * 0.05 * (1.0 - viscosity * 0.5);

    // Advected coordinate with viscosity damping
    let advectUV = uv - velocity * 0.02 * (1.0 - viscosity);

    // Read base video
    let videoCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Lava temperature with domain-warped FBM and Voronoi crust
    let tempNoise = fbm2D_dw(advectUV * 4.0 + time * 0.3, time, 5);
    let crustDetail = lavaCrustSDF(advectUV * 2.0, time);
    let temp = tempNoise + bass * 0.3 + mouseHeat + crustDetail * 0.2;

    // Temperature color with physics
    let lavaCol = temperatureColor(temp, time);

    // Molten surface detail with Fresnel
    let crustVoro = voronoi(advectUV * 8.0 - time * 0.5);
    let crustMask = smoothstep(0.05, 0.0, crustVoro.x);
    let crustTemp = crustMask * 0.3;
    let crustCol = mix(
        vec3<f32>(0.3, 0.15, 0.05),
        vec3<f32>(0.6, 0.3, 0.1),
        smoothstep(-0.1, 0.1, crustDetail)
    );

    // Molten surface with Fresnel reflection
    let surfaceNormal = normalize(vec3<f32>(crustDetail, crustVoro.x - crustVoro.y, 0.5));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cosTheta = max(dot(surfaceNormal, viewDir), 0.0);
    let f0 = vec3<f32>(0.15, 0.05, 0.02); // Molten F0
    let fresnel = fresnelSchlick(cosTheta, f0);
    var moltenLava = mix(lavaCol, crustCol + fresnel * 0.5, crustMask * 0.4);

    // Add molten cracks
    let cracks = smoothstep(0.6, 0.8, crustDetail) * 0.5;
    moltenLava += vec3<f32>(1.0, 0.6, 0.2) * cracks * (1.0 + bass * 0.5);

    // Decay/feedback blend with video using temporal coherence
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0).rgb;
    let feedback = mix(prev * decay, mix(videoCol, moltenLava, 0.6), 1.0 - decay);

    // Heat shimmer (chromatic distortion) with Voronoi pattern
    let shimmer = sin(uv.y * 100.0 + time * 10.0 + bass * 3.0) * bass * 0.003;
    let shimmerVoro = voronoi(uv * 20.0 + time * 0.5).x * 0.001;
    let totalShimmer = shimmer + shimmerVoro;
    let rSample = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(totalShimmer, 0.0), 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let bSample = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(totalShimmer, 0.0), 0.0).b;
    let chromaticVideo = vec3<f32>(rSample, gSample, bSample);

    // Blend video with lava
    var finalCol = mix(chromaticVideo, feedback, 0.5 + bass * 0.3);

    // Add heat glow with Beer-Lambert volumetric falloff
    let glowRadius = 0.3 + bass * 0.2 + mids * 0.1;
    let centerDist = length(uv - vec2<f32>(0.5));
    let glowDensity = exp(-centerDist * centerDist / (glowRadius * glowRadius)) * heatGlow;
    let glowCol = vec3<f32>(1.0, 0.4, 0.1);
    // Beer-Lambert extinction through the hot medium
    let glowExtinction = beerLambert(glowDensity * 2.0, 0.5 + bass * 0.3);
    finalCol = finalCol + glowCol * glowDensity * (0.5 + bass) * glowExtinction;

    // Mouse heat glow with volumetric falloff
    if (mouseDown) {
        let mouseGlow = exp(-mouseDist * mouseDist * 20.0) * 0.8;
        let mouseBeer = beerLambert(mouseGlow * 3.0, 0.8);
        finalCol += vec3<f32>(1.0, 0.3, 0.05) * mouseGlow * mouseBeer;
    }

    // Depth: fluid height + temperature
    let depth = temp * 0.5 + 0.25 + crustDetail * 0.1;

    // Sparkle on hot spots with Voronoi distribution
    if (treble > 0.5 && temp > 0.7) {
        let sparkVoro = voronoi(uv * 50.0 + time * 2.0);
        let spark = hash1(sparkVoro.x * 100.0 + time * 10.0);
        if (spark > 0.97) {
            finalCol = finalCol + vec3<f32>(1.0, 0.9, 0.7) * treble * 0.5 * (1.0 + bass * 0.3);
        }
    }

    // Turbulent bubbles from low frequency audio
    if (bass > 0.4) {
        let bubbleVoro = voronoi(uv * 30.0 + time * 0.5);
        let bubbleMask = smoothstep(0.02, 0.0, bubbleVoro.x) * smoothstep(0.15, 0.0, bubbleVoro.y - bubbleVoro.x);
        finalCol += vec3<f32>(1.0, 0.7, 0.3) * bubbleMask * bass * 0.3;
    }

    let _luma_sl = dot(clamp(finalCol, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.299, 0.587, 0.114));
    let _alpha_sl = clamp(_luma_sl * 0.7 + 0.2 + glowDensity * 0.3, 0.0, 1.0);

    textureStore(writeTexture, id.xy, vec4<f32>(clamp(finalCol, vec3<f32>(0.0), vec3<f32>(2.0)), _alpha_sl));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    // Temporal feedback for next frame
    textureStore(dataTextureA, id.xy, vec4<f32>(clamp(finalCol, vec3<f32>(0.0), vec3<f32>(1.0)), _alpha_sl));
}
