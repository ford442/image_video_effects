// ═══════════════════════════════════════════════════════════════════
//  Mycelium Network - Diffusion-limited aggregation like fungal mycelium
//  Category: generative
//  Features: procedural, branching, bioluminescent tips
//  Created: 2026-03-22
//  By: Agent 4A
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

// Hash and noise functions
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// FBM
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = pp * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// Distance to line segment
fn distToSegment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = uv - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// Branch structure
struct Branch {
    start: vec2<f32>,
    end: vec2<f32>,
    age: f32,
    isTip: f32,
    generation: f32,
};

// Generate mycelium branches
fn generateMycelium(uv: vec2<f32>, t: f32, growthRate: f32, branching: f32, seed: vec2<f32>) -> vec4<f32> {
    var minDist = 1000.0;
    var branchData = vec4<f32>(0.0); // x=dist, y=age, z=isTip, w=generation
    
    // Generate branching structure
    let numRoots = 3;
    for (var r: i32 = 0; r < numRoots; r++) {
        let rootAngle = f32(r) * 2.094 + hash21(seed + f32(r)) * 0.5;
        let rootPos = vec2<f32>(cos(rootAngle), sin(rootAngle)) * 0.1;
        
        var currentPos = rootPos;
        var currentDir = vec2<f32>(cos(rootAngle), sin(rootAngle));
        var age = 0.0;
        var generation = 0.0;
        
        // Grow branches
        let maxBranches = i32(20.0 + branching * 50.0);
        for (var i: i32 = 0; i < maxBranches; i++) {
            let fi = f32(i);
            
            // Branch length varies with age
            let length = 0.05 * (1.0 - fi / f32(maxBranches)) * growthRate;
            
            // Wandering direction
            let wanderAngle = noise(currentPos * 5.0 + t * 0.1 + fi) * 1.5;
            currentDir = normalize(currentDir + vec2<f32>(cos(wanderAngle), sin(wanderAngle)) * 0.3);
            
            let endPos = currentPos + currentDir * length;
            
            // Distance to this segment
            let dist = distToSegment(uv, currentPos, endPos);
            
            // Is this a tip?
            let isTip = 1.0 - fi / f32(maxBranches);
            
            if (dist < minDist) {
                minDist = dist;
                branchData = vec4<f32>(dist, age, isTip, generation);
            }
            
            // Branch probabilistically
            let branchProb = branching * 0.3 * (1.0 - fi / f32(maxBranches));
            if (hash21(currentPos + fi) < branchProb) {
                // Create side branch
                let branchAngle = wanderAngle + 0.8;
                let branchDir = normalize(currentDir + vec2<f32>(cos(branchAngle), sin(branchAngle)));
                let branchEnd = currentPos + branchDir * length * 0.7;
                
                let branchDist = distToSegment(uv, currentPos, branchEnd);
                if (branchDist < minDist) {
                    minDist = branchDist;
                    branchData = vec4<f32>(branchDist, age, isTip * 0.8, generation + 1.0);
                }
            }
            
            currentPos = endPos;
            age = fi / f32(maxBranches);
            generation += 0.1;
        }
    }
    
    return vec4<f32>(minDist, branchData.y, branchData.z, branchData.w);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let growthRate = mix(0.3, 2.0, u.zoom_params.x);
    let branching = mix(0.1, 0.8, u.zoom_params.y);
    let nutrientDensity = mix(0.3, 1.0, u.zoom_params.z);
    let biolumIntensity = mix(0.5, 3.0, u.zoom_params.w);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    
    // Animated seed for continuous growth
    let growthPhase = fract(t * 0.05 * growthRate);
    let seed = vec2<f32>(floor(t * 0.05 * growthRate), 0.0);
    
    // Get mycelium data
    let mycel = generateMycelium(p, t, growthRate, branching, seed);
    let dist = mycel.x;
    let age = mycel.y;
    let isTip = mycel.z;
    let generation = mycel.w;
    
    // Earthy brown colors for hyphae (get darker with age)
    let youngCol = vec3<f32>(0.6, 0.45, 0.3);
    let oldCol = vec3<f32>(0.25, 0.15, 0.1);
    let hyphaeCol = mix(youngCol, oldCol, age);
    
    // Thickness varies with generation
    let thickness = 0.003 * (1.0 - generation * 0.1);
    
    // Hyphae visibility
    let hyphaeMask = smoothstep(thickness * 2.0, 0.0, dist);
    let hyphaeCore = smoothstep(thickness, 0.0, dist);
    
    // Bioluminescent tips
    let tipPulse = sin(t * 3.0 + age * 10.0) * 0.5 + 0.5;
    let tipGlow = isTip * exp(-dist * 30.0) * biolumIntensity * (0.5 + tipPulse * 0.5);
    let tipCol = vec3<f32>(0.2, 0.9, 0.4) * tipGlow;
    
    // Nutrient field (background glow)
    let nutrient = fbm(p * 3.0 + t * 0.1, 4);
    let nutrientCol = vec3<f32>(0.1, 0.08, 0.05) * nutrient * nutrientDensity;
    
    // Combine
    var col = nutrientCol;
    col = mix(col, hyphaeCol, hyphaeMask);
    col = col + vec3<f32>(0.3, 0.2, 0.15) * hyphaeCore * 0.5;
    col = col + tipCol;
    
    // Age rings around growth centers
    let ringDist = length(p) - growthPhase * 2.0;
    let rings = sin(ringDist * 20.0) * 0.5 + 0.5;
    col = col + hyphaeCol * rings * 0.1 * (1.0 - age);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;
    
    // Store feedback for growth accumulation
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    col = max(col, prev * 0.98); // Persistent growth
    
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(age * 0.5, 0.0, 0.0, 0.0));
}
