// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Tree Fractal
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba, temporal-branch-sway, chromatic-leaves,
//            bass-growth-speed, aces-tone-map
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-10-10
//  Ideas: terminal leaf discs at every tip; rotating ideal-polygon geodesics of the Poincaré disk;
//         Poincaré metric-thinning branch strokes; negative-space horocycle rings
//  A packing: ACES display RGBA (read back as colour history)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// Returns (branch distance, terminal-leaf distance) in Möbius-mapped disk coordinates.
fn hyperbolicTree(p: vec2<f32>, time: f32, bass: f32, mids: f32, depth: i32, branchAngle: f32) -> vec2<f32> {
    var d = 1000.0;
    let r = length(p);
    if (r > 0.98) { return vec2<f32>(d, d); }
    
    let mobius = p / (1.0 + sqrt(max(1.0 - r * r, 0.0001)));
    
    var pos = vec2<f32>(0.0, 0.0);
    var dir = vec2<f32>(0.0, 1.0);
    let len0 = 0.25;
    
    for (var i: i32 = 0; i < depth; i = i + 1) {
        let fi = f32(i);
        // Temporal sway memory: each branch remembers previous sway
        let prevSway = sin(time * 0.3 + fi * 0.5) * 0.1;
        let len = len0 * pow(0.65, fi) * (1.0 + bass * 0.2 * sin(time + fi));
        let sway = sin(time * 0.5 + fi * 0.7) * 0.15 * (1.0 + mids * 0.3) + prevSway;
        let leftDir = vec2<f32>(dir.x * cos(branchAngle + sway) - dir.y * sin(branchAngle + sway),
                                 dir.x * sin(branchAngle + sway) + dir.y * cos(branchAngle + sway));
        let rightDir = vec2<f32>(dir.x * cos(-branchAngle + sway) - dir.y * sin(-branchAngle + sway),
                                  dir.x * sin(-branchAngle + sway) + dir.y * cos(-branchAngle + sway));
        
        let nextPos = pos + dir * len;
        // Idea 3 — Poincaré metric thinning: equal hyperbolic branch widths occupy
        // progressively fewer Euclidean pixels as their segment approaches the rim.
        let segMid = (pos + nextPos) * 0.5;
        let metricThin = clamp(1.0 - dot(segMid, segMid), 0.08, 1.0);
        d = min(d, sdSegment(mobius, pos, nextPos) - len * 0.08 * metricThin);
        
        // Descend into the child whose half-plane holds this point (HEAD used per-pixel hash noise
        // here, so every pixel walked a random path and the tree rendered as speckle).
        let rel = mobius - nextPos;
        let side = dir.x * rel.y - dir.y * rel.x;
        pos = nextPos;
        dir = select(rightDir, leftDir, side > 0.0);
    }
    // Idea 1 — terminal leaf: a disc just past this path's final tip.
    let tipLen = len0 * pow(0.65, f32(depth));
    let leafR = max(tipLen * 0.9, 0.012);
    let leafD = length(mobius - (pos + dir * leafR * 0.8)) - leafR;
    return vec2<f32>(d, leafD);
}

// Idea 2 — ideal N-gon geodesic: distance to the arcs orthogonal to the unit circle
// (centre 1/cos(pi/N), radius tan(pi/N)), folded into one angular sector.
fn idealPolygonDist(p: vec2<f32>, n: f32, rot: f32) -> f32 {
    let sector = 6.28318530718 / n;
    let a = atan2(p.y, p.x) - rot;
    let af = (fract(a / sector) - 0.5) * sector;
    let q = length(p) * vec2<f32>(cos(af), sin(af));
    let halfA = 3.14159265359 / n;
    return abs(length(q - vec2<f32>(1.0 / cos(halfA), 0.0)) - tan(halfA));
}

// Idea 4 — horocycles: Euclidean circles internally tangent to the Poincaré rim.
// Their sparse, drifting ideal points leave them as quiet rings in the tree's negative space.
fn horocycleDist(p: vec2<f32>, time: f32) -> f32 {
    var d = 1000.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        let fi = f32(i);
        let angle = fi * 2.39996323 + time * (0.008 + fi * 0.0015);
        let anchor = vec2<f32>(cos(angle), sin(angle));
        let radius = 0.11 + 0.055 * fract(fi * 0.61803399 + 0.17);
        let center = anchor * (1.0 - radius);
        d = min(d, abs(length(p - center) - radius));
    }
    return d;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let resolution = vec2<f32>(u.config.zw);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    
    let param1 = u.zoom_params.x;
    let param2 = u.zoom_params.y;
    let param3 = u.zoom_params.z;
    let param4 = u.zoom_params.w;
    
    let p = (uv - 0.5) * 2.0;
    let r = length(p);
    
    // Bass drives growth speed (depth changes more dynamically)
    let treeDepth = i32(mix(5.0, 12.0, param1 + bass * 0.3 * sin(time * 0.5)));
    let branchAngle = mix(0.3, 0.8, param2);
    let tree = hyperbolicTree(p, time, bass, mids, treeDepth, branchAngle);
    let d = tree.x;
    let tipLeaf = smoothstep(0.006, 0.0, tree.y);
    
    let diskEdge = smoothstep(0.95, 1.0, r);
    
    let branchGlow = smoothstep(0.05, 0.0, d);
    let leafGlow = smoothstep(0.15, 0.0, d) * (1.0 - smoothstep(0.0, 0.05, d));
    
    // Chromatic leaf separation: R leaves on left, B on right
    let leafHue = fract(0.25 + r * 0.3 + time * 0.02 + mids * 0.1 + param3 * 0.2);
    let leftLeaf = mix(leafHue, 0.0, smoothstep(-0.1, 0.5, p.x));
    let rightLeaf = mix(leafHue, 0.55, smoothstep(-0.5, 0.1, p.x));
    let blendedHue = mix(leftLeaf, rightLeaf, smoothstep(-0.1, 0.1, p.x));
    
    let sat = mix(0.3, 0.9, param4 + treble * 0.3);
    let val = mix(0.1, 1.0, branchGlow + leafGlow * 0.5 + bass * 0.15);
    
    let rgb = hue2rgb(blendedHue) * sat + vec3<f32>(1.0 - sat) * val;
    let leafColor = vec3<f32>(0.2, 0.8, 0.3) * leafGlow * (1.0 + treble);
    
    let tipColor = hue2rgb(blendedHue) * tipLeaf * (1.1 + treble * 0.5);

    // Geodesic lattice: two ideal polygons (N and 2N) slowly counter-rotating; lines thin toward the rim
    // the way the hyperbolic metric shrinks them.
    let geoWidth = 0.006 * (1.0 - r * r) + 0.0008;
    let geoD = min(idealPolygonDist(p, 7.0, time * 0.03), idealPolygonDist(p, 14.0, -time * 0.045));
    let geoLine = smoothstep(geoWidth, 0.0, geoD) * (1.0 - diskEdge) * (1.0 - branchGlow) * step(r, 1.0);
    let geoColor = hue2rgb(leafHue + 0.5) * geoLine * 0.28;

    // Horocycles remain subordinate to the tree and geodesic lattice by yielding wherever
    // occupied structure is present; the Poincaré factor keeps their rim contact delicate.
    let horoWidth = 0.001 + 0.0025 * max(1.0 - r * r, 0.0);
    let negativeSpace = 1.0 - clamp(branchGlow + leafGlow * 0.8 + tipLeaf + geoLine, 0.0, 1.0);
    let horoRing = smoothstep(horoWidth, 0.0, horocycleDist(p, time)) *
                   negativeSpace * (1.0 - diskEdge) * step(r, 1.0);
    let horoColor = hue2rgb(leafHue + 0.18) * horoRing * (0.08 + mids * 0.035);

    // Temporal branch glow persistence (exact load; HEAD filtered an rgba32float history)
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    let finalRGB = mix(rgb * val + leafColor + tipColor + geoColor + horoColor, prev * 0.92, 0.05 + bass * 0.02);
    
    let alpha = clamp(val * 0.6 + branchGlow * 0.3 + leafGlow * 0.2 + tipLeaf * 0.3 +
                      geoLine * 0.15 + horoRing * 0.04 + 0.1 + bass * 0.05, 0.0, 1.0) *
                (1.0 - diskEdge);
    let finalColor = vec4<f32>(acesToneMap(finalRGB * 1.1), alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(val * 0.5 + tipLeaf * 0.1, 0.0, 0.0, 0.0));
}
