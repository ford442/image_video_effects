// ═══════════════════════════════════════════════════════════════
//  Holographic Shatter - Shattered hologram with interference physics
//  Category: artistic
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, shard diffraction, 60Hz flicker
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=CellScale, y=HoloIntensity, z=Displacement, w=GlitchSpeed
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const N_AIR: f32 = 1.0;
const N_EMULSION: f32 = 1.52;
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// Physics Functions
// ═══════════════════════════════════════════════════════════════

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Thin-film interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Shard edge diffraction (edges of broken hologram diffract more)
fn shardEdgeDiffraction(edgeDist: f32, shardAngle: f32, wavelength: f32) -> f32 {
    // Maximum diffraction at shard edges
    let edgeFactor = exp(-edgeDist * edgeDist * 20.0);
    let angleFactor = sin(shardAngle * 5.0 + wavelength * 10.0) * 0.5 + 0.5;
    return edgeFactor * angleFactor;
}

// Shard interference spectrum
fn shardInterference(uv: vec2<f32>, shardId: vec2<f32>, shardAngle: f32, time: f32) -> vec3<f32> {
    // Each shard has slightly different optical properties
    let shardPhase = dot(shardId, vec2<f32>(12.9898, 78.233)) * 0.1;
    let opticalPath = 0.42 + sin(shardAngle + shardPhase + time * 0.2) * 0.06;
    
    let r = thinFilmInterference(opticalPath, LAMBDA_R, 1.0);
    let g = thinFilmInterference(opticalPath, LAMBDA_G, 1.0);
    let b = thinFilmInterference(opticalPath, LAMBDA_B, 1.0);
    
    return vec3<f32>(r, g, b);
}

// 60Hz flicker
fn projectionFlicker(time: f32) -> f32 {
    return 0.9 + 0.1 * sin(time * 377.0);
}

// Holographic scanlines
fn holographicScanlines(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
    let scanPos = (uv.y + uv.x * 0.1) * 100.0 + time * speed;
    let scanline = sin(scanPos) * 0.5 + 0.5;
    return scanline;
}

// ═══════════════════════════════════════════════════════════════
// Voronoi Structure
// ═══════════════════════════════════════════════════════════════

struct VoronoiResult {
    dist: f32,
    id: vec2<f32>,
    center: vec2<f32>
};

fn voronoi(uv: vec2<f32>, scale: f32) -> VoronoiResult {
    let g = floor(uv * scale);
    let f = fract(uv * scale);

    var res = VoronoiResult(8.0, vec2<f32>(0.0), vec2<f32>(0.0));

    for(var y: i32 = -1; y <= 1; y = y + 1) {
        for(var x: i32 = -1; x <= 1; x = x + 1) {
            let lattice = vec2<f32>(f32(x), f32(y));
            var offset = hash22(g + lattice);
            var p = lattice + offset - f;
            let d = dot(p, p);

            if(d < res.dist) {
                res.dist = d;
                res.id = g + lattice;
                res.center = (g + lattice + offset) / scale;
            }
        }
    }

    res.dist = sqrt(res.dist);
    return res;
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let scale = u.zoom_params.x * 30.0 + 5.0;
    let holoIntensity = u.zoom_params.y;
    let displaceStr = u.zoom_params.z;
    let speed = u.zoom_params.w * 5.0;

    // Voronoi Grid (shards)
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let v = voronoi(aspectUV, scale);

    // Mouse Interaction
    let cellCenter = v.center;
    let mouseVec = cellCenter - vec2<f32>(mousePos.x * aspect, mousePos.y);
    let distToMouse = length(mouseVec);
    let shardAngle = atan2(mouseVec.y, mouseVec.x);

    // Animate shard offset
    var offset = vec2<f32>(0.0);
    var active = 0.0;

    // Only affect shards near mouse
    if (distToMouse < 0.4 && distToMouse > 0.001) {
        let falloff = 1.0 - smoothstep(0.0, 0.4, distToMouse);
        active = falloff;

        // Push shards away and rotate slightly
        var dir = normalize(mouseVec);
        offset = dir * falloff * displaceStr * 0.2;

        // Add some jitter based on ID
        let jitter = (hash22(v.id) - 0.5) * 0.05 * falloff * displaceStr;
        offset = offset + jitter;
    }

    let finalUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // ═══════════════════════════════════════════════════════════════
    // Shard Interference Physics
    // ═══════════════════════════════════════════════════════════════
    
    let interference = shardInterference(uv, v.id, shardAngle, time);
    
    // Apply Holographic Effect to shards
    let scanline = holographicScanlines(uv, time, speed);

    // Interference color (Cyan/Magenta shift)
    if (holoIntensity > 0.0) {
        let idVal = v.id.x * 12.9898 + v.id.y * 78.233;
        let shift = sin(time * speed + idVal) * 0.5 + 0.5;

        // Mix in scanline with interference
        let holoColor = vec3<f32>(0.0, 1.0, 1.0) * shift + vec3<f32>(1.0, 0.0, 1.0) * (1.0 - shift);
        let interferenceColor = interference * (1.0 + shift);

        // Effect strength blends based on mouse proximity + base intensity
        let effectStr = max(active * displaceStr * 2.0, holoIntensity * 0.3);

        // Additive blend with interference modulation
        color = color + vec4<f32>(mix(holoColor, interferenceColor, 0.5) * effectStr * scanline, 0.0);

        // Desaturate slightly to look more "digital"
        let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
        color = mix(color, vec4<f32>(vec3<f32>(gray), color.a), effectStr * 0.5);
    }

    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation with Shard Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Base hologram transparency
    let base_alpha = 0.05;
    
    // Shard edge diffraction boost
    let edgeDist = v.dist; // Distance to shard center (0 at center, higher at edges)
    let normalizedEdge = 1.0 - smoothstep(0.0, 0.3, edgeDist); // 1 at edge, 0 at center
    
    let edgeDiffractionR = shardEdgeDiffraction(edgeDist, shardAngle, LAMBDA_R);
    let edgeDiffractionG = shardEdgeDiffraction(edgeDist, shardAngle, LAMBDA_G);
    let edgeDiffractionB = shardEdgeDiffraction(edgeDist, shardAngle, LAMBDA_B);
    let edgeDiffraction = (edgeDiffractionR + edgeDiffractionG + edgeDiffractionB) / 3.0;
    
    // Interference contribution
    let diffraction_efficiency = (interference.r + interference.g + interference.b) / 3.0;
    
    // Alpha boosted at shard edges and active shards
    var alpha = base_alpha + diffraction_efficiency * 0.3 + edgeDiffraction * 0.2;
    alpha += active * 0.1; // Active shards more visible
    
    // Scanline alpha modulation
    alpha *= 0.85 + scanline * 0.15;
    
    // 60Hz flicker
    alpha *= projectionFlicker(time);
    
    // Shard edge highlight with alpha boost
    let edgeHighlight = smoothstep(0.25, 0.3, edgeDist) * (1.0 - smoothstep(0.3, 0.35, edgeDist));
    alpha += edgeHighlight * 0.1;
    color += vec4<f32>(interference * 0.3, 0.0) * edgeHighlight;
    
    // Highlight edges of active shards
    if (active > 0.0) {
        color = color + vec4<f32>(0.1, 0.1, 0.2, 0.0) * active;
        alpha += active * 0.05;
    }
    
    // Pepper's ghost reflection between shards
    let ghost_uv = uv + vec2<f32>(0.002, 0.002);
    let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb * interference;
    color = vec4<f32>(mix(color.rgb, ghost, PEPPER_GHOST_REFLECTION * (1.0 + active)), color.a);
    
    // Speckle noise
    let speckle = hash22(uv * 100.0 + vec2<f32>(time));
    alpha *= 0.94 + speckle.x * 0.12;
    
    // Cap alpha
    alpha = min(alpha, 0.5);
    
    // Apply alpha to color
    color.a = alpha;

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    
    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
