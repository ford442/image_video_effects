// ═══════════════════════════════════════════════════════════════════
//  Kinetic Neo-Brutalist Megastructure
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: grinding interlock with friction seams; server-core slits with rack LEDs
//  A packing: ACES display RGBA (C read as colour history)
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Block Density, y=Repulsion Radius, z=Neon Intensity, w=Travel Speed
    ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn distributionGGX(N: vec3<f32>, H: vec3<f32>, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let NdotH = max(dot(N, H), 0.0);
    let NdotH2 = NdotH * NdotH;
    let denom = NdotH2 * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * denom * denom);
}

fn fresnelSchlick(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    let ct = clamp(1.0 - cosTheta, 0.0, 1.0);
    let ct5 = ct * ct * ct * ct * ct;
    return F0 + (vec3<f32>(1.0) - F0) * ct5;
}

fn geometrySmith(N: vec3<f32>, V: vec3<f32>, L: vec3<f32>, roughness: f32) -> f32 {
    let NdotV = max(dot(N, V), 0.0);
    let NdotL = max(dot(N, L), 0.0);
    let ggx1 = NdotV / (NdotV * (1.0 - roughness) + roughness);
    let ggx2 = NdotL / (NdotL * (1.0 - roughness) + roughness);
    return ggx1 * ggx2;
}

fn hash13(p3: vec3<f32>) -> f32 {
    var p3_mod = fract(p3 * 0.1031);
    p3_mod += dot(p3_mod, p3_mod.yzx + 33.33);
    return fract((p3_mod.x + p3_mod.y) * p3_mod.z);
}

fn buildingParamsFromHash(h: f32) -> vec4<f32> {
    let height = 1.0 + h * 3.5;
    let roughness = 0.2 + h * 0.6;
    let neon = step(0.7, h);
    let btype = floor(h * 4.0);
    return vec4<f32>(height, roughness, neon, btype);
}

fn getBuildingParams(id: vec3<f32>) -> vec4<f32> {
    return buildingParamsFromHash(hash13(id));
}

fn volumetricFog(ro: vec3<f32>, rd: vec3<f32>, tMax: f32) -> vec4<f32> {
    let fogDensity = 0.08;
    let transmittance = exp(-fogDensity * tMax);
    let fogColor = vec3<f32>(0.05, 0.06, 0.08);
    return vec4<f32>(fogColor * (1.0 - transmittance), transmittance);
}

const SPACING: f32 = 4.0;

// Block-local position (sway + domain repetition) and the cell it belongs to.
fn swayed(p: vec3<f32>) -> vec3<f32> {
    return p + vec3<f32>(sin(u.config.x * 0.5) * 2.0, 0.0, 0.0);
}

// Idea 1: grinding interlock — per-building stroke of the secondary mass along its joint.
fn grindStroke(h: f32) -> f32 {
    let bass = plasmaBuffer[0].x;
    let phase = u.config.x * (0.35 + h * 0.4) * (0.5 + u.zoom_params.w * 0.25) + h * 6.2831853;
    return sin(phase) * (0.35 + bass * 0.15);
}

// returns (distance, material id = hash + neon*10, friction seam weight)
fn map(p: vec3<f32>) -> vec3<f32> {
    var pos = swayed(p);
    let cell = round(pos / SPACING);
    pos = pos - SPACING * cell;
    let hc = hash13(cell);
    let params = buildingParamsFromHash(hc);
    let h = params.x;
    let neon = params.z;
    let btype = params.w;
    let stroke = grindStroke(hc);
    var d = 1000.0;
    var seam = 0.0;
    if (btype < 1.0) {
        d = sdBox(pos, vec3<f32>(1.5, h, 1.5));
    } else if (btype < 2.0) {
        let b1 = sdBox(pos, vec3<f32>(1.5, h, 1.5));
        // slot cutter slides vertically along the shaft
        let b2 = sdBox(pos - vec3<f32>(0.0, stroke * h * 0.6, 0.0), vec3<f32>(1.6, 0.5, 0.5));
        d = max(b1, -b2);
        seam = 1.0 - smoothstep(0.0, 0.06, abs(b2));
    } else if (btype < 3.0) {
        let b1 = sdBox(pos, vec3<f32>(1.2, h * 0.8, 1.2));
        // cap slab grinds up and down over the core
        let b2 = sdBox(pos - vec3<f32>(0.0, h * 0.5 + stroke * 0.5, 0.0), vec3<f32>(1.5, 0.8, 1.5));
        d = smin(b1, b2, 0.5);
        seam = 1.0 - smoothstep(0.0, 0.12, abs(b1 - b2));
    } else {
        let b1 = sdBox(pos, vec3<f32>(1.5, h, 1.5));
        // side mass slides in and out of the main body
        let b2 = sdBox(pos - vec3<f32>(1.0 + stroke * 0.45, h * 0.3, 0.0), vec3<f32>(0.8, h * 0.6, 0.8));
        d = smin(b1, b2, 0.6);
        seam = 1.0 - smoothstep(0.0, 0.12, abs(b1 - b2));
    }
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * 10.0;
    let mouseY = (u.zoom_config.z * 2.0 - 1.0) * 10.0;
    // repulsion field rides 15 units ahead of the flying camera so the pointer stays live
    let camZ = -10.0 + u.config.x * u.zoom_params.w;
    let mouse_pos = vec3<f32>(mouseX, mouseY, camZ + 15.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        d += (u.zoom_params.y - dist_to_mouse) * 0.5;
    }
    return vec3<f32>(d, hc + neon * 10.0, seam);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }
    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / max(f32(dims.y), 1.0);
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let ro = vec3<f32>(0.0, 0.0, -10.0 + time * u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));
    var t = 0.0;
    var mat_id = 0.0;
    var seam = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if (res.x < 0.001 || t > 50.0) {
            mat_id = res.y;
            seam = res.z;
            break;
        }
        t += res.x;
    }
    var col = vec3<f32>(0.01);
    var alpha = 0.0;
    let hit = t < 50.0;
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let V = -rd;
        let L = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let H = normalize(V + L);
        // material id carries the same cell hash map() used (hash + neon*10)
        let neonFlag = step(5.0, mat_id);
        let cellHash = mat_id - neonFlag * 10.0;
        let params = buildingParamsFromHash(cellHash);
        let roughness = params.y;
        let neon = params.z;
        let NdotL = max(dot(n, L), 0.0);
        let F0 = vec3<f32>(0.04);
        let F = fresnelSchlick(max(dot(H, V), 0.0), F0);
        let D = distributionGGX(n, H, roughness);
        let G = geometrySmith(n, V, L, roughness);
        let numerator = D * G * F;
        let denominator = 4.0 * max(dot(n, V), 0.0) * NdotL + 0.001;
        let specular = numerator / denominator;
        let diffuse = vec3<f32>(0.3, 0.32, 0.35) * NdotL * (vec3<f32>(1.0) - F);
        let baseColor = diffuse + specular;
        let neonCol = vec3<f32>(0.0, 1.0, 0.8) * step(0.5, neon) * (0.5 + 0.5 * sin(time * 4.0 + bass * 6.0));
        col = baseColor * u.zoom_params.x + neonCol * u.zoom_params.z * (1.0 + bass);

        // Idea 1: friction seam — hot glow where the sliding mass grinds against the body,
        // strongest while the stroke is moving fast (derivative of grindStroke's sine).
        let local = swayed(p) - SPACING * round(swayed(p) / SPACING);
        let strokeSpeed = abs(cos(time * (0.35 + cellHash * 0.4) * (0.5 + u.zoom_params.w * 0.25) + cellHash * 6.2831853));
        let friction = seam * (0.35 + 0.65 * strokeSpeed) * (1.0 + bass * 0.6);
        col += vec3<f32>(1.0, 0.42, 0.12) * friction * 1.4;

        // Idea 2: server-core slits — horizontal board-form slits on vertical faces of neon
        // buildings let the hidden cyan core show, with rack LEDs blinking along each slit.
        let vertical = 1.0 - smoothstep(0.3, 0.6, abs(n.y));
        let slitRow = local.y * 2.2;
        let slit = (1.0 - smoothstep(0.03, 0.07, abs(fract(slitRow) - 0.5))) * vertical * neon;
        let along = select(local.x, local.z, abs(n.x) > abs(n.z));
        let ledCell = vec3<f32>(floor(along * 6.0), floor(slitRow), cellHash * 97.0);
        let ledSeed = hash13(ledCell);
        let ledCenter = abs(fract(along * 6.0) - 0.5);
        let blink = pow(0.5 + 0.5 * sin(time * (2.0 + ledSeed * 6.0) + ledSeed * 40.0), 6.0);
        let led = slit * (1.0 - smoothstep(0.12, 0.3, ledCenter)) * blink * (1.0 + treble * 2.0);
        let ledTint = mix(vec3<f32>(0.0, 1.0, 0.8), vec3<f32>(1.0, 0.25, 0.3), step(0.85, ledSeed));
        col += (vec3<f32>(0.0, 0.55, 0.45) * slit * (0.6 + bass) + ledTint * led * 2.0) * u.zoom_params.z;

        let fog = volumetricFog(ro, rd, t);
        col = col * fog.a + fog.rgb;
        // semantic alpha: fog-attenuated coverage lifted by emissive neon, slits and friction
        alpha = clamp(0.45 + 0.4 * fog.a + neonFlag * 0.1 + slit * 0.2 + friction * 0.3, 0.0, 1.0);
    }

    // ═══ temporal feedback (dataTextureC colour history → dataTextureA) ═══
    let prev = textureLoad(dataTextureC, coords, 0);
    col = mix(col, prev.rgb * 0.92, 0.05 + bass * 0.01);

    // ═══ chromatic offset ═══
    let caStr = 0.003 * (1.0 + bass) + u.zoom_params.z * 0.001;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    col = acesToneMap(col * 1.2);

    // depth from hit distance (near = 1, sky = 0)
    let depth = select(0.0, clamp(1.0 - t / 50.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coords, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coords, vec4<f32>(col, alpha));
}
