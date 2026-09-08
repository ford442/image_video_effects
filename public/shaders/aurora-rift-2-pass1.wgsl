// ═══════════════════════════════════════════════════════════════════
//  aurora-rift-2-pass1
//  Category: lighting-effects
//  Features: multi-pass-1, volumetric, curl-flow, audio-reactive, depth-aware
//  Ideas: Birkeland plasma vortex tubes, ionospheric substorm flash bursts, multi-scale layer diffusion coupling
//  A packing: volumetric data [RGB=aurora color, A=density] for Pass 2 compositor
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,       // x=time, y=globalIntensity, z=resX, w=resY
    zoom_params: vec4<f32>,       // x=scale, y=flowSpeed, z=diffusionRate, w=fbmOctaves
    zoom_config: vec4<f32>,       // x=rotationSpeed, y=depthParallax, z=emitThresh, w=chromaticSpread
    ripples:     array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> f32 {
    var h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash4(p: vec4<f32>) -> f32 {
    let dot4 = dot(p, vec4<f32>(1.0, 57.0, 113.0, 157.0));
    return fract(sin(dot4) * 43758.5453123);
}

fn noise4d(p: vec4<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    
    var sum = 0.0;
    for (var w: i32 = 0; w <= 1; w = w + 1) {
        for (var z: i32 = 0; z <= 1; z = z + 1) {
            for (var y: i32 = 0; y <= 1; y = y + 1) {
                for (var x: i32 = 0; x <= 1; x = x + 1) {
                    let corner = i + vec4<f32>(f32(x), f32(y), f32(z), f32(w));
                    let wx = select(1.0 - uu.x, uu.x, x == 1);
                    let wy = select(1.0 - uu.y, uu.y, y == 1);
                    let wz = select(1.0 - uu.z, uu.z, z == 1);
                    let ww = select(1.0 - uu.w, uu.w, w == 1);
                    sum = sum + (wx * wy * wz * ww) * hash4(corner);
                }
            }
        }
    }
    return sum * 2.0 - 1.0;
}

fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum = sum + amp * (hash2(p * freq + time * 0.1) - 0.5);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>(n2 - n4, n1 - n3) / (2.0 * eps);
}

fn voronoiCell(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    var best = 1e5;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let cellPos = i + vec2<f32>(f32(x), f32(y));
            let seed = vec2<f32>(hash2(cellPos), hash2(cellPos + 13.37));
            let point = cellPos + seed - 0.5;
            let d = length(point - f);
            best = min(best, d);
        }
    }
    return best;
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    var c = v * s;
    let h6 = h * 6.0;
    var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }
    
    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let time = u.config.x;
    let aspect = dims.x / max(dims.y, 1.0);
    
    // Enhanced parameters
    let scale = u.zoom_params.x * 3.0 + 1.0;
    let flowSpeed = u.zoom_params.y * 2.0 + 0.5;
    let diffRate = u.zoom_params.z; // Live diffusion slider!
    let fbmOctaves = i32(u.zoom_params.w * 5.0 + 2.0);
    let depthParallax = u.zoom_config.y * 0.6 + 0.1;
    let emitThresh = u.zoom_config.z * 0.3 + 0.1;
    
    // 3-band audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sample depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Distance-based LOD
    let dist = length(uv - 0.5);
    let lodOctaves = i32(mix(f32(fbmOctaves), 2.0, smoothstep(0.3, 0.6, dist)));
    
    // Build the curl-flow field (depth-aware)
    let curl = curlNoise(uv * scale + depth * depthParallax, time * flowSpeed);
    
    // Multi-layer parallax with enhanced layering
    var totalWarp = vec2<f32>(0.0);
    var totalWeight = 0.0;
    
    let w0 = 1.0 / (1.0 + abs(depth - 0.0) * 12.0);
    let a0 = curlNoise(uv * scale + curl * 0.3, time * flowSpeed);
    totalWarp += a0 * depthParallax * w0;
    totalWeight += w0;
    
    let w1 = 1.0 / (1.0 + abs(depth - 0.5) * 12.0);
    let a1 = curlNoise(uv * scale + curl * 0.3, time * flowSpeed * 2.0);
    totalWarp += a1 * depthParallax * w1;
    totalWeight += w1;
    
    let w2 = 1.0 / (1.0 + abs(depth - 1.0) * 12.0);
    let a2 = curlNoise(uv * scale + curl * 0.3, time * flowSpeed * 3.0);
    totalWarp += a2 * depthParallax * w2;
    totalWeight += w2;
    
    totalWarp = totalWarp / max(totalWeight, 0.0001);
    
    // Voronoi + FBM hybrid (cellular foam)
    let cellDist = voronoiCell(uv * scale * 2.0 + totalWarp);
    let fbmVal = fbm(uv * scale * 4.0 + curl, time, lodOctaves);
    let foamPattern = smoothstep(0.0, 0.12, cellDist) * 0.6 + smoothstep(0.2, 0.4, fbmVal) * 0.4;
    
    // 4-D hyper-noise
    let hyper = noise4d(vec4<f32>(uv * scale * 1.5, time * 0.4, depth * 2.0));
    let hyperMod = (hyper + 1.0) * 0.5;
    
    // Phase-interference wavefronts
    let waveA = sin(length(uv - 0.5) * 28.0 - time * 3.2);
    let waveB = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 22.0 + time * 2.7);
    let waveC = sin(dot(uv - 0.5, vec2<f32>(1.1, 0.9)) * 30.0 - time * 4.1);
    let interference = (waveA * waveB * waveC + 1.0) * 0.5;
    
    var pattern = (foamPattern * 0.4 + hyperMod * 0.3 + interference * 0.3) *
                  (1.0 + (1.0 - depth) * 1.5);
    
    // IDEA 1: Birkeland current plasma vortex tubes
    // Paired magnetic vortex sheaths along auroral ribbons with high-speed helical spinning
    let vortexAngle = atan2(totalWarp.y, totalWarp.x);
    let vortexTube = sin(vortexAngle * 4.0 + length(totalWarp) * 35.0 - time * 6.0);
    let vortexSheath = smoothstep(0.3, 0.9, abs(vortexTube)) * length(curl);
    pattern += vortexSheath * (0.4 + mids * 0.4);

    // Emissive plasma on cell borders
    let border = smoothstep(emitThresh, 1.0, smoothstep(0.08, 0.12, cellDist) * pattern * length(curl));
    let plasma = hsv2rgb(fract(time * 0.07 + pattern + hyper + bass * 0.1), 0.9, 1.0);
    
    // Enhanced aurora color with violet / magenta ionospheric glow
    let auroraBase = hsv2rgb(fract(0.25 + pattern * 0.25), 0.85, 0.92);
    var auroraColor = mix(auroraBase, plasma, border * 0.6);

    // IDEA 2: Ionospheric geomagnetic substorm flash bursts
    // Treble and click ripples ignite localized geomagnetic substorm flares with intense N2+ violet boundary glow
    var substormGlow = vec3<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.5) {
            let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let rFlare = exp(-abs(rDist - elapsed * 0.3) * 30.0) * exp(-elapsed * 1.4);
            substormGlow += vec3<f32>(0.6, 0.2, 0.9) * rFlare * (1.0 + treble * 1.5);
        }
    }
    auroraColor += substormGlow;

    var density = pattern * (1.0 + border * 2.5) + length(substormGlow) * 0.5;

    // IDEA 3: Multi-scale layer diffusion coupling
    // diffRate actively diffuses density and blends temporal state from dataTextureC
    let prevHistory = textureLoad(dataTextureC, coord, 0);
    let prevDensity = prevHistory.a;
    let prevColor = prevHistory.rgb;

    let temporalMix = clamp(diffRate * 0.45 + 0.05, 0.0, 0.6);
    density = mix(density, prevDensity, temporalMix);
    auroraColor = mix(auroraColor, prevColor, temporalMix * 0.65);
    
    let ign = fract(52.9829189 * fract(dot(vec2<f32>(gid.xy), vec2<f32>(0.06711056, 0.00583715))));
    let ditheredColor = auroraColor + (ign - 0.5) * (1.0 / 255.0);

    let volumetric = vec4<f32>(ditheredColor, density);
    textureStore(dataTextureA, coord, volumetric);
    
    let inputColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0);
    textureStore(writeTexture, coord, inputColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
