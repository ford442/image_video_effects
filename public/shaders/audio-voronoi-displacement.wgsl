// ═══════════════════════════════════════════════════════════════════
//  audio-voronoi-displacement
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, voronoi, audio-fft, displacement-mapping
//  Upgraded: 2026-03-22
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

// ═══ AUDIO SIMULATION ═══
fn getAudioBands(uv: vec2<f32>, time: f32) -> vec3<f32> {
    // Simulated audio bands from plasma buffer if available
    var bass = 0.0;
    var mid = 0.0;
    var treble = 0.0;
    
    // Sample from extra buffer for audio-like data
    let bufSize = 256;
    let idx = i32(uv.x * 10.0) % bufSize;
    if (u32(idx) < arrayLength(&extraBuffer) / 4) {
        bass = extraBuffer[idx * 4] * 2.0;
        mid = extraBuffer[idx * 4 + 1] * 2.0;
        treble = extraBuffer[idx * 4 + 2] * 2.0;
    }
    
    // Fallback to procedural audio simulation
    if (bass < 0.01) {
        let beat = sin(time * 8.0) * 0.5 + 0.5;
        bass = pow(beat, 2.0) * 0.5 + 0.1;
        mid = sin(time * 12.0 + uv.x * 10.0) * 0.5 + 0.5;
        treble = sin(time * 20.0 + uv.y * 15.0) * 0.5 + 0.5;
    }
    
    return vec3<f32>(clamp(bass, 0.0, 1.0), clamp(mid, 0.0, 1.0), clamp(treble, 0.0, 1.0));
}

// ═══ VORONOI WITH AUDIO ═══
fn voronoiAudio(p: vec2<f32>, cellCount: f32, audioBands: vec3<f32>, time: f32) -> vec4<f32> {
    let cellSize = cellCount;
    let i = floor(p * cellSize);
    let f = fract(p * cellSize);
    
    var minDist1 = 1000.0;
    var minDist2 = 1000.0;
    var cellId = vec2<f32>(0.0);
    var cellCenter = vec2<f32>(0.0);
    
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
            } else if (dist < minDist2) {
                minDist2 = dist;
            }
        }
    }
    
    return vec4<f32>(minDist1, minDist2, cellId.x, cellCenter.x);
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
    
    // Get simulated audio bands
    let audioBands = getAudioBands(uv, time);
    
    // Calculate Voronoi with audio-reactive cells
    let voronoi = voronoiAudio(uv, cellCount, audioBands * audioReact, time);
    let dist1 = voronoi.x;
    let dist2 = voronoi.y;
    let cellHash = hash12(vec2<f32>(voronoi.z, voronoi.w));
    
    // Cell boundary
    let edge = smoothstep(0.05, 0.15, dist2 - dist1);
    
    // Audio-reactive displacement
    let cellCenter = voronoi.w;
    let toCenter = vec2<f32>(cos(cellHash * 6.28), sin(cellHash * 6.28));
    let audioDisplacement = toCenter * audioBands.x * displacement;
    
    // Displace UV based on cell and audio
    let displacedUV = clamp(uv + audioDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
    
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
    
    // Add cell edge glow
    let edgeGlow = (1.0 - edge) * audioBands.y * 0.5;
    color += vec3<f32>(edgeGlow * 0.8, edgeGlow * 0.6, edgeGlow);
    
    // Treble sparkle
    let sparkle = step(0.95, hash12(vec2<f32>(voronoi.z + time * 0.1))) * audioBands.z;
    color += vec3<f32>(sparkle);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.7, 1.0, audioBands.x * audioReact + edgeGlow);
    
    textureStore(writeTexture, id, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(2.0)), alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - audioBands.x * 0.1), 0.0, 0.0, 0.0));
}
