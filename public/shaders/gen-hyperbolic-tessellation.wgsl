// ═══════════════════════════════════════════════════════════════════════════════
//  Hyperbolic Tessellation Engine
//  Category: GENERATIVE | Complexity: VERY_HIGH
//  Recursive hyperbolic geometry in real-time. Non-Euclidean tiles subdivide
//  infinitely, colored by their recursive depth. M.C. Escher meets fractals
//  in the Poincaré disk model.
//  Mathematical approach: Poincaré disk model with Möbius isometries, hyperbolic
//  distance metric, recursive tiling via {p,q} Schläfli symbols, geodesic arc
//  rendering, depth-based coloring with interference patterns.
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=TileP, y=MouseX, z=MouseY, w=ColorMode
    zoom_params: vec4<f32>,  // x=RotationSpeed, y=RecursionDepth, z=EdgeGlow, w=Zoom
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Complex arithmetic
// ─────────────────────────────────────────────────────────────────────────────
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b) + 1e-12;
    return vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d;
}

fn cconj(z: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(z.x, -z.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Möbius transformation in the Poincaré disk
//  Maps z → (z - a) / (1 - conj(a)*z) — isometry of hyperbolic plane
// ─────────────────────────────────────────────────────────────────────────────
fn hyperbolicMobius(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
    let num = z - a;
    let den = vec2<f32>(1.0, 0.0) - cmul(cconj(a), z);
    return cdiv(num, den);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hyperbolic distance in Poincaré disk
// ─────────────────────────────────────────────────────────────────────────────
fn hyperbolicDist(a: vec2<f32>, b: vec2<f32>) -> f32 {
    let diff = a - b;
    let denom = 1.0 - 2.0 * dot(a, b) + dot(a, a) * dot(b, b);
    let delta = dot(diff, diff) / max(denom, 1e-8);
    return log(1.0 + 2.0 * delta + 2.0 * sqrt(delta * (delta + 1.0) + 1e-8));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reflect point across a geodesic circle in the Poincaré disk
//  Circle: center c, radius r (hyperbolic)
// ─────────────────────────────────────────────────────────────────────────────
fn reflectGeodesic(z: vec2<f32>, center: vec2<f32>, radius: f32) -> vec2<f32> {
    let translated = hyperbolicMobius(z, center);
    let r = length(translated);
    let reflected = translated * (radius * radius) / max(r * r, 1e-8);
    return hyperbolicMobius(reflected, -center);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hyperbolic rotation (rotation in the disk preserves hyperbolic metric)
// ─────────────────────────────────────────────────────────────────────────────
fn hyperRotate(z: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(z.x * c - z.y * s, z.x * s + z.y * c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hash
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tile the hyperbolic plane using {p, q} tiling
//  Repeatedly reflects across fundamental domain edges
//  Returns: (distance to nearest edge, recursion depth, cell ID)
// ─────────────────────────────────────────────────────────────────────────────
fn tilePoincare(z_in: vec2<f32>, p: f32, q: f32, maxIter: i32) -> vec3<f32> {
    var z = z_in;
    let pi = 3.14159265;

    // Fundamental domain edge parameters for {p, q} tiling
    let angleP = pi / p;
    let angleQ = pi / q;

    // Geodesic mirror distance from center
    let cosP = cos(angleP);
    let cosQ = cos(angleQ);
    let sinP = sin(angleP);
    let mirrorDist = sqrt((cosQ * cosQ - sinP * sinP) / (1.0 - sinP * sinP + 1e-6));

    var depth = 0.0;
    var cellId = 0.0;

    for (var i = 0; i < maxIter; i++) {
        // Reflect across rotational symmetry planes of the p-gon
        let theta = atan2(z.y, z.x);
        let sector = floor(theta / (2.0 * angleP) + 0.5);
        let foldAngle = sector * 2.0 * angleP;
        z = hyperRotate(z, -foldAngle);
        if (z.y < 0.0) {
            z.y = -z.y;
            depth += 1.0;
        }
        cellId += sector * pow(p, f32(i));

        // Reflect across the geodesic edge (hyperbolic reflection)
        let edgeCenter = vec2<f32>(mirrorDist, 0.0);
        let distToEdge = hyperbolicDist(z, edgeCenter);
        if (distToEdge < 0.5) {
            z = hyperbolicMobius(z, edgeCenter);
            z = z * (-1.0);
            z = hyperbolicMobius(z, -edgeCenter);
            depth += 1.0;
        }
    }

    // Distance to nearest fundamental domain edge
    let theta = atan2(z.y, z.x);
    let edgeDist = min(abs(sin(theta * p * 0.5)), abs(length(z) - mirrorDist * 0.5));

    return vec3<f32>(edgeDist, depth, cellId);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = (fragCoord * 2.0 - dims) / min(dims.x, dims.y);
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let rotSpeed = u.zoom_params.x * 1.5 + 0.1;            // 0.1 – 1.6
    let maxDepth = i32(u.zoom_params.y * 12.0 + 4.0);      // 4 – 16
    let edgeGlow = u.zoom_params.z * 2.0 + 0.3;            // 0.3 – 2.3
    let zoom = u.zoom_params.w * 0.5 + 0.5;                // 0.5 – 1.0
    let tileP = floor(u.zoom_config.x * 4.0 + 4.0);       // 4 – 8 (polygon sides)
    let tileQ = 3.0;                                        // meeting at vertex
    let colorMode = u.zoom_config.w;                        // 0 – 1

    // ─────────────────────────────────────────────────────────────────────────
    //  Map to Poincaré disk
    // ─────────────────────────────────────────────────────────────────────────
    var z = uv * zoom;
    let r = length(z);

    // Outside the disk → dark space
    if (r >= 0.99) {
        let outerGlow = exp(-(r - 1.0) * 20.0) * 0.1;
        let col = vec3<f32>(0.05, 0.08, 0.15) * outerGlow;
        textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
        return;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Animate: slow rotation + drift
    // ─────────────────────────────────────────────────────────────────────────
    z = hyperRotate(z, time * rotSpeed * 0.1);

    // Mouse interaction: Möbius translation toward mouse
    let mouseUV = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / dims * 2.0 - 1.0) * 0.3;
    let mouseInDisk = mouseUV * min(length(mouseUV), 0.5) / max(length(mouseUV), 0.001);
    z = hyperbolicMobius(z, mouseInDisk * 0.2);

    // ─────────────────────────────────────────────────────────────────────────
    //  Tile the hyperbolic plane
    // ─────────────────────────────────────────────────────────────────────────
    let tileResult = tilePoincare(z, tileP, tileQ, maxDepth);
    let edgeDist = tileResult.x;
    let depth = tileResult.y;
    let cellId = tileResult.z;

    // ─────────────────────────────────────────────────────────────────────────
    //  Coloring based on recursion depth and cell identity
    // ─────────────────────────────────────────────────────────────────────────
    let normalizedDepth = depth / f32(maxDepth);

    // Color scheme 1: rainbow depth
    let hue1 = fract(normalizedDepth * 2.0 + time * 0.05 + hash21(vec2<f32>(cellId, depth)) * 0.3);
    let sat1 = 0.7 + 0.3 * sin(depth * 1.5);
    let val1 = 0.9 - normalizedDepth * 0.5;
    let col1 = hsv2rgb(hue1, sat1, val1);

    // Color scheme 2: cool/warm alternation
    let warm = vec3<f32>(0.95, 0.5, 0.2);
    let cool = vec3<f32>(0.15, 0.4, 0.9);
    let alt = sin(depth * 3.14159 * 0.5 + cellId * 0.1);
    let col2 = mix(cool, warm, alt * 0.5 + 0.5) * val1;

    var tileColor = mix(col1, col2, colorMode);

    // ─────────────────────────────────────────────────────────────────────────
    //  Edge rendering: geodesic arcs glow
    // ─────────────────────────────────────────────────────────────────────────
    let edgeWidth = 0.02 + 0.01 * sin(time * 2.0);
    let edgeLine = smoothstep(edgeWidth, edgeWidth * 0.3, edgeDist);
    let edgeColor = hsv2rgb(fract(time * 0.1 + depth * 0.15), 0.5, 1.0);
    tileColor = mix(tileColor, edgeColor, edgeLine * edgeGlow);

    // ─────────────────────────────────────────────────────────────────────────
    //  Depth fade: tiles shrink to infinity at disk boundary
    // ─────────────────────────────────────────────────────────────────────────
    let diskFade = 1.0 - smoothstep(0.85, 0.99, r);
    tileColor *= diskFade;

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: hyperbolic waves
    // ─────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let rpUV = (rp.xy * dims * 2.0 - dims) / min(dims.x, dims.y) * zoom;
        let hDist = hyperbolicDist(z, rpUV);
        let age = time - rp.z;
        if (age > 0.0 && age < 5.0) {
            let wave = sin(hDist * 15.0 - age * 3.0) * exp(-hDist * 2.0) * exp(-age * 0.5);
            tileColor += edgeColor * wave * 0.3;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Subtle disk border ring
    // ─────────────────────────────────────────────────────────────────────────
    let borderRing = exp(-abs(r - 0.98) * 200.0) * 0.3;
    tileColor += vec3<f32>(0.5, 0.7, 1.0) * borderRing;

    // Tone mapping
    tileColor = tileColor / (tileColor + vec3<f32>(1.0));
    tileColor = pow(tileColor, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(tileColor, 1.0));
}
