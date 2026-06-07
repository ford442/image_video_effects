// ═══════════════════════════════════════════════════════════════════
//  Liquid-Crystal Hive-Mind
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, upgraded-rgba,
//            aces-tone-map, temporal-feedback, chromatic-aberration,
//            depth-aware, raymarched
//  Complexity: Very High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
//  By: Codex F1 flagship reference pass
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Cell Density, y=Fluid Turbulence, z=Sync Pulse, w=Disruption Radius
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn huePreserveClamp(color: vec3<f32>, limit: f32) -> vec3<f32> {
    let peak = max(max(color.r, color.g), color.b);
    return color / max(1.0, peak / max(limit, 0.001));
}

fn bass_env(prev: f32, bass: f32) -> f32 {
    let k = select(0.08, 0.35, bass > prev);
    return mix(prev, bass, k);
}

// Custom mod function
fn mod_f32(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn mod_vec2(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}

// https://iquilezles.org/articles/palettes/
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// --- NOISE ---
fn hash(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_smooth = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(dot(hash(p + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                       dot(hash(p + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), f_smooth.x),
                   mix(dot(hash(p + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                       dot(hash(p + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), f_smooth.x), f_smooth.y),
               mix(mix(dot(hash(p + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                       dot(hash(p + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), f_smooth.x),
                   mix(dot(hash(p + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                       dot(hash(p + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), f_smooth.x), f_smooth.y), f_smooth.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        f += amp * noise(pos);
        pos *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// Pseudo curl noise for fluid movement
fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    let e = 0.1;
    let dx = vec3<f32>(e, 0.0, 0.0);
    let dy = vec3<f32>(0.0, e, 0.0);
    let dz = vec3<f32>(0.0, 0.0, e);

    let x = (noise(p + dy) - noise(p - dy)) - (noise(p + dz) - noise(p - dz));
    let y = (noise(p + dz) - noise(p - dz)) - (noise(p + dx) - noise(p - dx));
    let z = (noise(p + dx) - noise(p - dx)) - (noise(p + dy) - noise(p - dy));

    return normalize(vec3<f32>(x, y, z)) / (2.0 * e);
}


// --- SDF Primitives ---
// Hexagonal Prism
fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735);
    var p_abs = abs(p);

    // dot2 equivalent logic for folding
    let dot_val = dot(k.xy, p_abs.xy);
    let max_val = max(dot_val, 0.0);
    p_abs.x -= 2.0 * min(max_val, 0.0) * k.x;
    p_abs.y -= 2.0 * max_val * k.y;

    // Not full implementation, using a simplified hex block for performance
    let d = vec2<f32>(
        max(p_abs.x * 0.866025 + p_abs.y * 0.5, p_abs.y) - h.x,
        p_abs.z - h.y
    );
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Hexagonal Grid Domain Repetition
// Returns local point and hex ID
struct HexGrid {
    uv: vec2<f32>,
    id: vec2<f32>,
}
fn opRepHex(p: vec2<f32>, size: f32) -> HexGrid {
    var p_scaled = p / size;
    let r = vec2<f32>(1.0, 1.73205081);
    let h = r * 0.5;

    let a = mod_vec2(p_scaled, r) - h;
    let b = mod_vec2(p_scaled - h, r) - h;

    var gv: vec2<f32>;
    var id: vec2<f32>;

    if (dot(a, a) < dot(b, b)) {
        gv = a;
        id = p_scaled - a;
    } else {
        gv = b;
        id = p_scaled - b;
    }

    return HexGrid(gv * size, id);
}

// --- Map Function ---
struct MapResult {
    d: f32,       // Distance
    mat: f32,     // Material ID (0: Wall, 1: Fluid)
    glow: f32,    // Inner glow intensity
    hexId: vec2<f32> // ID of the current hex cell
}

fn map(p: vec3<f32>, bass: f32, mids: f32, hivePulse: f32, mouseField: vec2<f32>) -> MapResult {
    var res: MapResult;

    let t = u.config.x;
    let audio = bass;

    // Sliders
    let density = u.zoom_params.x * (1.0 + mids * 0.12); // Cell Density
    let turbulence = u.zoom_params.y * (1.0 + bass * 0.35); // Fluid Turbulence
    let syncPulse = clamp(u.zoom_params.z + hivePulse * 0.35, 0.0, 3.0); // Sync Pulse
    let disruptRadius = u.zoom_params.w; // Disruption Radius

    // Mouse Interaction
    let aspect = u.config.z / u.config.w;
    var mousePos = vec2<f32>((u.zoom_config.y * 2.0 - 1.0) * aspect, -(u.zoom_config.z * 2.0 - 1.0));
    mousePos *= 8.0; // scale to world space roughly

    let mouseDist = length((p.xy + mouseField * p.z * 0.25) - mousePos);
    let mouseDown = u.zoom_config.w;
    let isDisrupted = (1.0 - smoothstep(0.0, disruptRadius * (2.2 + mouseDown * 1.8), mouseDist)) * (0.35 + mouseDown * 0.65);

    // Hex Grid
    let hexSize = 1.5 / density;
    let fieldAngle = (mouseField.x - mouseField.y) * 0.18 * isDisrupted;
    let grid = opRepHex(rot2D(fieldAngle) * p.xy, hexSize);
    let localP = vec3<f32>(grid.uv, p.z);

    // Cell walls (Hex Prism hollowed out)
    let outerHex = sdHexPrism(localP, vec2<f32>(hexSize * 0.45, 1.0));
    let innerHex = sdHexPrism(localP, vec2<f32>(hexSize * 0.40, 1.1));

    // Extrude based on audio and ID to create pulsing effect
    let cellHash = fract(sin(dot(grid.id, vec2<f32>(12.9898, 78.233))) * 43758.5453);

    // Sync logic: normally they pulse randomly, but syncPulse forces them to align
    let pulsePhase = mix(cellHash * 6.28, 0.0, syncPulse * 0.3);
    let cellHeightOffset = sin(t * (1.6 + mids * 0.5) + pulsePhase) * 0.2 * (1.0 + audio * 0.8 + hivePulse * 0.5);

    // Mouse disruption shatters/offsets cells
    let disruptOffset = isDisrupted * sin(cellHash * 100.0) * 0.5;

    // Final wall distance
    let wallDist = max(outerHex, -innerHex) + (cellHeightOffset + disruptOffset) * (p.z / 1.0); // Simple Z taper

    // Internal Fluid Volume
    // We don't render it as a hard surface, but as a bounding box for volumetric
    // However, we need a distance to step towards
    let fluidBounds = innerHex;

    // Fluid Displacement (Curl Noise)
    // The fluid is inside the cell, so we calculate turbulence based on global P
    let fluidMove = curlNoise(p * 0.5 + vec3<f32>(mouseField * 0.4, t * (0.35 + mids * 0.25)));
    let fluidTurbulence = fbm(p * 2.0 + fluidMove * turbulence * (1.0 + isDisrupted * 2.0));

    // Determine material
    if (wallDist < fluidBounds + 0.1) {
        res.d = wallDist * 0.5; // Scale down to avoid artifacts
        res.mat = 0.0; // Wall
        res.glow = 0.0;
    } else {
        // Fluid is boundless inside the cell, we just step through it
        res.d = fluidBounds * 0.5;
        res.mat = 1.0; // Fluid
        res.glow = fluidTurbulence;
    }

    res.hexId = grid.id;
    return res;
}

// Normal Calculation for Walls
fn calcNormal(p: vec3<f32>, bass: f32, mids: f32, hivePulse: f32, mouseField: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, bass, mids, hivePulse, mouseField).d - map(p - e.xyy, bass, mids, hivePulse, mouseField).d,
        map(p + e.yxy, bass, mids, hivePulse, mouseField).d - map(p - e.yxy, bass, mids, hivePulse, mouseField).d,
        map(p + e.yyx, bass, mids, hivePulse, mouseField).d - map(p - e.yyx, bass, mids, hivePulse, mouseField).d
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coord.x) >= res.x || f32(coord.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(coord) - 0.5 * res) / res.y;
    let uv01 = vec2<f32>(coord) / res;
    let previousState = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
    let bass = bass_env(previousState.r, plasmaBuffer[0].x);
    let mids = bass_env(previousState.g, plasmaBuffer[0].y);
    let treble = bass_env(previousState.b, plasmaBuffer[0].z);
    let hivePulse = previousState.a;
    let mouse = u.zoom_config.yz * 2.0 - vec2<f32>(1.0);
    let mouseField = vec2<f32>(mouse.x * res.x / max(res.y, 1.0), -mouse.y);

    // Camera setup - looking straight down Z
    let ro = vec3<f32>(mouseField * 0.18, -5.0);
    let rd = normalize(vec3<f32>(uv.x + mouseField.x * 0.035, uv.y + mouseField.y * 0.035, 1.0));

    var t_dist = 0.0;
    var max_t = 15.0;
    var p = ro;

    var col = vec3<f32>(0.0);
    var fluidAccum = vec3<f32>(0.0);
    var hitWall = false;
    var glowSum = 0.0;
    var depthHit = 1.0;

    let syncPulse = u.zoom_params.z;

    // Raymarching Loop
    for (var i = 0; i < 80; i++) {
        p = ro + rd * t_dist;
        let m = map(p, bass, mids, hivePulse, mouseField);

        if (m.mat == 0.0) {
            // Hitting wall
            if (m.d < 0.005) {
                hitWall = true;
                depthHit = clamp(t_dist / max_t, 0.0, 1.0);
                break;
            }
            t_dist += m.d;
        } else {
            // Inside fluid volume, accumulate color and step forward slightly
            // We use the 'glow' (turbulence) to determine color

            // Iridescent Palette based on depth and turbulence
            let a = vec3<f32>(0.5, 0.5, 0.5);
            let b = vec3<f32>(0.5, 0.5, 0.5);
            let c = vec3<f32>(1.0, 1.0, 1.0);
            let d = vec3<f32>(0.263, 0.416, 0.557); // Blue/Cyan/Purple vibes

            // Sync shift
            let cellHash = fract(sin(dot(m.hexId, vec2<f32>(12.9898, 78.233))) * 43758.5453);
            let colorShift = mix(cellHash, hivePulse, syncPulse * 0.4) + u.config.x * (0.08 + mids * 0.04) + treble * 0.08;

            let fluidColor = palette(m.glow + colorShift, a, b, c, d);

            // Accumulate
            // Deeper fluid = denser accumulation, audio boosts brightness
            let density = 0.045 * (1.0 + bass * 0.8 + treble * 0.25);
            fluidAccum += fluidColor * density * exp(-t_dist * 0.2);
            glowSum += m.glow * density;

            // Step forward through the fluid
            t_dist += max(0.05, m.d * 0.5);
        }

        if (t_dist > max_t) { break; }
    }

    if (hitWall) {
        let n = calcNormal(p, bass, mids, hivePulse, mouseField);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        let diff = max(dot(n, l), 0.0);

        // Shiny dark plastic/metal walls
        let baseColor = vec3<f32>(0.05);
        let spec = pow(max(dot(reflect(-l, n), -rd), 0.0), 32.0);

        col = baseColor * diff + vec3<f32>(0.8) * spec;

        // Add rim lighting from the fluid inside
        let rim = 1.0 - max(dot(n, -rd), 0.0);
        col += fluidAccum * pow(rim, 3.0) * 0.5;
    } else {
        // Just the fluid we accumulated
        col = fluidAccum;
    }

    // Vignette
    col *= 0.5 + 0.5 * pow(16.0 * uv01.x * uv01.y * (1.0 - uv01.x) * (1.0 - uv01.y), 0.25);

    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    let membrane = clamp(glowSum * 2.0 + select(0.0, 0.45, hitWall), 0.0, 1.0);
    let depthSignal = clamp(mix(1.0 - depthHit, inputDepth, 0.25) + membrane * 0.25, 0.0, 1.0);
    let alpha = clamp(0.18 + membrane * 0.72 + bass * 0.08, 0.18, 0.96);

    let chroma = (0.002 + treble * 0.003) * (0.4 + membrane);
    col = vec3<f32>(col.r + chroma, col.g, col.b - chroma * 0.6);
    col = huePreserveClamp(col * (1.1 + bass * 0.25), 3.0);
    col = acesToneMap(col);

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let finalColor = mix(inputColor.rgb, col, alpha);
    let finalAlpha = max(inputColor.a, alpha);
    let nextHivePulse = clamp(mix(hivePulse, membrane, 0.12 + bass * 0.04), 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthSignal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(bass, mids, treble, nextHivePulse));
}
