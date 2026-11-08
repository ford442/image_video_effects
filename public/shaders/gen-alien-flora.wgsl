// ═══════════════════════════════════════════════════════════════════
//  Alien Flora
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-08
//  Ideas: gill ridges; spore motes; margin bioluminescence; mycelial veins
//  A packing: linear history RGB + organic alpha (ACES on display)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Density, y=SwaySpeed, z=GlowIntensity, w=ColorShift

// Organic Material Properties
const TISSUE_DENSITY: f32 = 2.5;
const SCATTERING_COEFF: f32 = 1.8;
const ABSORPTION_BASE: f32 = 0.3;

// SDF Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Smooth Min for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 2D Rotation
fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Hash function for random values
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Calculate organic tissue thickness from SDF
fn calculateThickness(d: f32, normal: vec3<f32>, p: vec3<f32>) -> f32 {
    // Sample SDF slightly inside the surface
    let inner_d = map(p - normal * 0.1).x;
    // Thickness estimate based on surface gradient
    return max(0.05, min(1.0, abs(inner_d - d) * 5.0));
}

// Scene Map function
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Terrain
    let terrainHeight = sin(p.x * 0.2) * sin(p.z * 0.2) * 2.0 + sin(p.x * 0.5 + p.z * 0.3) * 0.5;
    let d_terrain = p.y - terrainHeight;

    // 2. Vegetation (Domain Repetition)
    let density = mix(16.0, 4.0, u.zoom_params.x);
    let cell_size = density;

    let id = floor(p.xz / cell_size);
    let q_xz = (fract(p.xz / cell_size) - 0.5) * cell_size;

    let rand = hash(id);

    let cell_center = (id + 0.5) * cell_size;
    let ground_y = sin(cell_center.x * 0.2) * sin(cell_center.y * 0.2) * 2.0 + sin(cell_center.x * 0.5 + cell_center.y * 0.3) * 0.5;

    var q = vec3<f32>(q_xz.x, p.y - ground_y, q_xz.y);

    // Swaying Motion
    var time = u.config.x;
    let swaySpeed = u.zoom_params.y;

    let swayAmount = 0.5 * (q.y * 0.1) * (q.y * 0.1);
    let sway = vec3<f32>(
        sin(time * swaySpeed + id.x) * swayAmount,
        0.0,
        cos(time * swaySpeed * 0.8 + id.y) * swayAmount
    );

    q.x -= sway.x;
    q.z -= sway.z;

    // Mushroom/Plant SDF
    let stemHeight = 2.0 + rand * 3.0;
    let stemRadius = 0.2 + rand * 0.1;
    let p_stem = q - vec3<f32>(0.0, stemHeight * 0.5, 0.0);
    let stem = sdCappedCylinder(p_stem, stemHeight * 0.5, stemRadius);

    let capRadius = 1.0 + rand * 1.5;
    let capHeight = 0.5 + rand * 0.5;
    let p_cap = q - vec3<f32>(0.0, stemHeight, 0.0);
    let d_cap_sphere = length(p_cap * vec3<f32>(1.0, 2.0, 1.0)) - capRadius;
    let d_cap_cut = max(d_cap_sphere, -p_cap.y);
    // Idea 1 — gill ridges on the cap underside
    let gillAng = atan2(p_cap.z, p_cap.x);
    let underside = smoothstep(0.12, -0.08, p_cap.y);
    let gillReach = smoothstep(0.2, 0.75, length(p_cap.xz) / max(capRadius, 0.2));
    let gill = abs(sin(gillAng * 12.0)) * 0.055 * underside * gillReach;
    let cap = d_cap_cut + gill;

    // Blend stem and cap
    let d_plant = smin(stem, cap, 0.3);

    // Idea 2 — spore motes lifting off the cap rim
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    var d_spore = 8.0;
    for (var s = 0; s < 3; s = s + 1) {
        let sf = f32(s);
        let ang = rand * 6.2831853 + sf * 2.094395;
        let lift = fract(time * (0.12 + bass * 0.22) + rand * 3.1 + sf * 0.37);
        let sporeP = vec3<f32>(
            cos(ang) * capRadius * 0.82,
            stemHeight + lift * (1.5 + bass * 0.9),
            sin(ang) * capRadius * 0.82
        );
        d_spore = min(d_spore, sdSphere(q - sporeP, 0.065 + treble * 0.03));
    }

    var d = d_terrain;
    var mat = 1.0;

    if (d_plant < d) {
        d = d_plant;
        mat = 2.0;
    }
    if (d_spore < d) {
        d = d_spore;
        mat = 3.0;
    }

    return vec2<f32>(d, mat);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.1;
    var mat = 0.0;
    for(var i=0; i<128; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 100.0) { break; }
        t += d;
    }
    return vec2<f32>(t, mat);
}

// Subsurface scattering calculation for organic tissue
fn subsurfaceScattering(n: vec3<f32>, l: vec3<f32>, v: vec3<f32>, thickness: f32, baseColor: vec3<f32>) -> vec3<f32> {
    // Back-scattering (translucency)
    let backDot = max(0.0, dot(n, -l));
    let scattering = pow(backDot, 3.0) * SCATTERING_COEFF;
    
    // Beer-Lambert absorption
    let absorption = exp(-vec3<f32>(thickness * ABSORPTION_BASE * 0.8, 
                                     thickness * ABSORPTION_BASE * 1.2, 
                                     thickness * ABSORPTION_BASE * 1.5));
    
    return baseColor * scattering * absorption * 2.0;
}

// Calculate organic alpha based on tissue properties
fn calculateOrganicAlpha(mat: f32, thickness: f32, n: vec3<f32>, l: vec3<f32>) -> f32 {
    if (mat == 1.0) {
        // Terrain - mostly opaque with slight variation
        return 0.95;
    }
    
    // Plant tissue - variable translucency
    // Thicker tissue = more opaque
    let baseAlpha = min(0.95, 0.4 + thickness * TISSUE_DENSITY);
    
    // Backlit areas more translucent
    let backlitFactor = max(0.0, dot(n, -l));
    let translucency = backlitFactor * 0.35;
    
    return mix(baseAlpha, baseAlpha * 0.65, translucency);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    // Rescue: gid.y grows downward, so the world rendered upside down (ground on top).
    uv.y = -uv.y;
    let dimsC = vec2<i32>(textureDimensions(dataTextureC));
    let prev = textureLoad(dataTextureC, clamp(vec2<i32>(global_id.xy), vec2<i32>(0), dimsC - vec2<i32>(1)), 0);

    // Camera Setup
    var mouse = u.zoom_config.yz;
    var time = u.config.x * 0.1;
    let yaw = (mouse.x - 0.5) * 10.0 + time;
    let pitch = ((mouse.y - 0.5)) * 2.0 + 0.5;
    let dist = 10.0;

    let target_pos = vec3<f32>(0.0, 2.0, time * 10.0);

    let ro = vec3<f32>(
        target_pos.x + sin(yaw) * dist,
        target_pos.y + pitch * 5.0 + 2.0,
        target_pos.z + cos(yaw) * dist
    );

    let forward = normalize(target_pos - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarch
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;

    var color = vec3<f32>(0.0);
    var alpha = 0.2;
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));

    if (t < 100.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);
        
        // Calculate tissue thickness for subsurface effects
        let thickness = calculateThickness(res.x, n, p);

        let diff = max(dot(n, lightDir), 0.0);

        // Color Palette
        var baseColor = vec3<f32>(0.1, 0.3, 0.1);

        if (mat == 2.0) {
            // Plant bioluminescent colors
            let shift = u.zoom_params.w;
            let hue = fract(p.x * 0.1 + p.z * 0.1 + shift);

            let k = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
            let p_col = abs(fract(vec3<f32>(hue) + k) * 6.0 - 3.0);
            let hueColor = clamp(p_col - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));

            baseColor = mix(vec3<f32>(0.2, 0.8, 0.9), hueColor, 0.5);

            // Glow intensity affects emission, not alpha directly
            let glow = u.zoom_params.z;
            baseColor = baseColor * glow;

            // ── Idea 3: margin bioluminescence — the light lives in the cap rim
            // and pulses down the stem; the pulse front rides mids.
            let cellSz = mix(16.0, 4.0, u.zoom_params.x);
            let cid = floor(p.xz / cellSz);
            let crand = hash(cid);
            let cq = (fract(p.xz / cellSz) - 0.5) * cellSz;
            let cc = (cid + 0.5) * cellSz;
            let gy = sin(cc.x * 0.2) * sin(cc.y * 0.2) * 2.0 + sin(cc.x * 0.5 + cc.y * 0.3) * 0.5;
            let stemH = 2.0 + crand * 3.0;
            let capR = 1.0 + crand * 1.5;
            let rimBand = smoothstep(0.65, 0.95, length(cq) / capR) * smoothstep(-0.4, 0.2, p.y - gy - stemH);
            let hgt = clamp((p.y - gy) / stemH, 0.0, 1.0);
            let pulse = smoothstep(0.85, 1.0, sin(hgt * 9.0 + u.config.x * (1.5 + plasmaBuffer[0].y * 2.5) + crand * 6.28) * 0.5 + 0.5);
            let stemMask = 1.0 - smoothstep(0.85, 1.0, hgt);
            baseColor += hueColor * glow * (rimBand * 1.4 + pulse * stemMask * 0.6);
        } else if (mat == 3.0) {
            let treble = plasmaBuffer[0].z;
            baseColor = vec3<f32>(0.72, 0.95, 1.0) * (0.7 + treble * 1.5);
        }

        // Apply subsurface scattering for organic materials
        if (mat == 2.0) {
            let sss = subsurfaceScattering(n, lightDir, -rd, thickness, baseColor);
            baseColor += sss;
        }

        // ── Idea 4: mycelial veins — the plants share a glowing root net on the
        // ground: branching radial veins around each plant's foot, fading outward.
        if (mat == 1.0) {
            let cellSzG = mix(16.0, 4.0, u.zoom_params.x);
            let gid2 = floor(p.xz / cellSzG);
            let gq = (fract(p.xz / cellSzG) - 0.5) * cellSzG;
            let gr = length(gq);
            let gang = atan2(gq.y, gq.x) + hash(gid2) * 6.28;
            let vein = smoothstep(0.82, 1.0, abs(sin(gang * 4.0 + log(gr + 0.3) * 3.0)))
                     + smoothstep(0.9, 1.0, abs(sin(gang * 9.0 - log(gr + 0.3) * 5.0))) * 0.5;
            let reach = exp(-gr / (cellSzG * 0.22));
            let veinCol = mix(vec3<f32>(0.2, 0.8, 0.9), vec3<f32>(0.6, 0.3, 1.0), fract(u.zoom_params.w));
            baseColor += veinCol * vein * reach * u.zoom_params.z * 0.35 * (0.6 + plasmaBuffer[0].x * 0.8);
        }

        // Shading
        let ambient = vec3<f32>(0.05, 0.1, 0.1);
        color = baseColor * (diff * 0.5 + 0.5);

        // Rim light for atmosphere
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        color += vec3<f32>(0.5, 0.8, 1.0) * rim * 0.5;

        // Distance Fog
        let fogAmount = 1.0 - exp(-t * 0.05);
        color = mix(color, fogColor, fogAmount);
        
        // Calculate organic alpha
        alpha = calculateOrganicAlpha(mat, thickness, n, lightDir);
        
        // Bioluminescent areas have slightly lower alpha for glow effect
        if (mat == 2.0 && u.zoom_params.z > 0.7) {
            alpha = mix(alpha, 0.75, 0.3);
        }

    } else {
        color = fogColor;
        color = mix(fogColor, vec3<f32>(0.0, 0.0, 0.05), rd.y * 0.5 + 0.5);
        alpha = 0.18;
    }

    let decay = 0.96;
    let temporal = mix(prev.rgb * decay, color, 0.25);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(temporal, alpha));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesToneMap(color), alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
