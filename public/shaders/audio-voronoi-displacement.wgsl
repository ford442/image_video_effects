// ═══════════════════════════════════════════════════════════════════
//  audio-voronoi-displacement
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, voronoi, audio-fft, displacement-mapping
//  Upgraded: 2026-11-01
//  Ideas: site bulge; visible ridge
//  A packing: ACES display RGBA (C is not read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hash22 ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn getAudioBands() -> vec3<f32> {
    return clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct VoronoiCell {
    dist1: f32,
    dist2: f32,
    cellX: f32,
    centerX: f32,
    toSite: vec2<f32>,
};

// ═══ VORONOI WITH AUDIO ═══
fn voronoiAudio(p: vec2<f32>, cellCount: f32, audioBands: vec3<f32>, time: f32) -> VoronoiCell {
    let cellSize = cellCount;
    let i = floor(p * cellSize);
    let f = fract(p * cellSize);
    
    var minDist1 = 1000.0;
    var minDist2 = 1000.0;
    var cellId = vec2<f32>(0.0);
    var cellCenter = vec2<f32>(0.0);
    var toSite = vec2<f32>(0.0);
    
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cell = i + neighbor;
            
            // Hash-based random position with audio modulation
            var hashVal = hash22(cell);
            let bassMod = audioBands.x * 0.3;
            let midMod = audioBands.y * 0.2;
            
            // Animate cell centers with audio
            hashVal += vec2<f32>(
                sin(time * (1.0 + hashVal.x) + cell.x * 0.5) * bassMod,
                cos(time * (1.0 + hashVal.y) + cell.y * 0.5) * midMod
            );
            
            let point = neighbor + hashVal;
            let dist = length(point - f);
            
            if (dist < minDist1) {
                minDist2 = minDist1;
                minDist1 = dist;
                cellId = cell;
                cellCenter = hashVal;
                toSite = (point - f) / max(cellSize, 0.001);
            } else if (dist < minDist2) {
                minDist2 = dist;
            }
        }
    }

    var cell: VoronoiCell;
    cell.dist1 = minDist1;
    cell.dist2 = minDist2;
    cell.cellX = cellId.x;
    cell.centerX = cellCenter.x;
    cell.toSite = toSite;
    return cell;
}

// ═══ MAIN ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let cellCount = mix(5.0, 30.0, u.zoom_params.x);    // x: Cell count
    let audioReact = u.zoom_params.y * 2.0;              // y: Audio reactivity
    let displacement = mix(0.0, 0.1, u.zoom_params.z);   // z: Displacement strength
    let colorIntensity = mix(0.3, 1.5, u.zoom_params.w); // w: Color intensity
    
    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let distToMouse = length(uv - mousePos);
    let mouseGravity = 1.0 - smoothstep(0.0, 0.25, distToMouse);
    let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 35.0 - time * 7.0) * exp(-distToMouse * 5.0);
    
    let audioBands = getAudioBands();

    // Calculate Voronoi with audio-reactive cells
    let voronoi = voronoiAudio(uv, cellCount, audioBands * audioReact, time);
    let dist1 = voronoi.dist1;
    let dist2 = voronoi.dist2;
    let cellHash = hash12(vec2<f32>(voronoi.cellX, voronoi.centerX));

    // Cell boundary: 0 on the wall, 1 inside
    let edge = smoothstep(0.05, 0.15, dist2 - dist1);
    let ridge = 1.0 - edge;

    // Audio-reactive displacement (hash slide kept) plus a bulge toward the site.
    let toCenter = vec2<f32>(cos(cellHash * 6.28), sin(cellHash * 6.28));
    let audioDisplacement = toCenter * audioBands.x * displacement;
    // ── Idea 1: site bulge
    // The vector to the nearest site was computed and discarded. The
    // displacement slider still sets the length; bass pushes on a silence floor.
    let siteLen = max(length(voronoi.toSite), 1e-4);
    let siteDir = voronoi.toSite / siteLen;
    let bulge = siteDir * displacement * (0.55 + audioBands.x);

    let cursorDir = (uv - mousePos) + vec2<f32>(0.001, 0.0);
    let cursorDisplacement = cursorDir / max(length(cursorDir), 0.001) * mouseGravity * 0.05 + clickPulse * 0.03;
    let displacedUV = clamp(uv + audioDisplacement + bulge + cursorDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Sample image at displaced position
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
    
    // Color based on frequency bands per cell
    let freqColor = vec3<f32>(
        audioBands.x * cellHash * 1.5,
        audioBands.y * fract(cellHash * 1.618) * 1.5,
        audioBands.z * fract(cellHash * 2.618) * 1.5
    );
    
    // Blend based on audio intensity
    color = mix(color, color * (1.0 + freqColor), audioReact * 0.5);
    color *= colorIntensity;
    color *= (1.0 + mouseGravity * 0.5);

    // ── Idea 2: visible ridge
    // The wall between the two nearest sites is dark even in silence.
    // Mids still brighten it.
    color = mix(color, color * 0.55, ridge * 0.75);
    let edgeGlow = ridge * (0.12 + audioBands.y * 0.45);
    color += vec3<f32>(edgeGlow * 0.8, edgeGlow * 0.6, edgeGlow);
    color += vec3<f32>(mouseGravity * 0.3, mouseGravity * 0.2, mouseGravity * 0.4);
    
    // Treble sparkle
    let sparkle = step(0.95, hash12(vec2<f32>(voronoi.cellX, floor(time * 4.0)))) * audioBands.z;
    color += vec3<f32>(sparkle);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let shiftMag = clamp(length(audioDisplacement + bulge) * 8.0, 0.0, 1.0);
    let alpha = clamp(0.4 + ridge * 0.35 + shiftMag * 0.2 + mouseGravity * 0.15, 0.0, 1.0);
    let display = vec4<f32>(acesToneMap(max(color, vec3<f32>(0.0))), alpha);

    textureStore(writeTexture, id, display);
    textureStore(dataTextureA, id, display);
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - audioBands.x * 0.1), 0.0, 0.0, 0.0));
}
