// ═══════════════════════════════════════════════════════════════════════════════
//  gen-prismatic-bismuth-lattice.wgsl - 3D Bismuth Crystal Growth
//  
//  Upgraded: 2026-08-21 (Batch 42)
//  Techniques:
//    - Hopper growth simulation (Crystallographic preferred growth)
//    - Audio-reactive iridescence and growth rate via plasmaBuffer
//    - Temporal accumulation trails via dataTextureC
//    - Distance-based alpha for depth composition
// ═══════════════════════════════════════════════════════════════════════════════

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

const PI: f32 = 3.14159265359;

// Bismuth hopper crystal distance estimator
fn bismuthDE(pos: vec3<f32>, time: f32, audioReact: f32) -> vec2<f32> {
    var p = pos;
    let scale = 1.5 + audioReact * 0.2;
    var d = 1e10;
    var id = 0.0;
    
    // Fractal folding for hopper growth patterns
    for (var i = 0; i < 4; i = i + 1) {
        p = abs(p) - vec3<f32>(0.5, 0.5, 0.5) * scale;
        
        // Rotate
        let c = cos(time * 0.1);
        let s = sin(time * 0.1);
        p = vec3<f32>(c*p.x - s*p.z, p.y, s*p.x + c*p.z);
        
        // Hopper stepping (staircase structure)
        let stepSize = 0.2;
        p -= round(p / stepSize) * stepSize * 0.1;
        
        // Box distance
        let q = abs(p) - vec3<f32>(0.4);
        let boxD = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
        
        if (boxD < d) {
            d = boxD;
            id = f32(i);
        }
    }
    
    return vec2<f32>(d * 0.5, id);
}

// Thin-film interference iridescence
fn iridescence(thickness: f32, normal: vec3<f32>, viewDir: vec3<f32>) -> vec3<f32> {
    let cosTheta = abs(dot(normal, viewDir));
    let pathLength = thickness / max(cosTheta, 0.1);
    
    // Phase shift colors
    return vec3<f32>(
        0.5 + 0.5 * cos(pathLength * 3.0 + 0.0),
        0.5 + 0.5 * cos(pathLength * 3.0 + 2.0),
        0.5 + 0.5 * cos(pathLength * 3.0 + 4.0)
    );
}

fn calcNormal(pos: vec3<f32>, time: f32, audioReact: f32) -> vec3<f32> {
    let eps = 0.001;
    let e = vec2<f32>(eps, 0.0);
    return normalize(vec3<f32>(
        bismuthDE(pos + e.xyy, time, audioReact).x - bismuthDE(pos - e.xyy, time, audioReact).x,
        bismuthDE(pos + e.yxy, time, audioReact).x - bismuthDE(pos - e.yxy, time, audioReact).x,
        bismuthDE(pos + e.yyx, time, audioReact).x - bismuthDE(pos - e.yyx, time, audioReact).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    let zoom = 3.0 + u.zoom_params.y * 2.0; 
    let theta = time * 0.2;
    let phi = sin(time * 0.1) * 0.5;
    let camPos = vec3<f32>(cos(theta) * cos(phi) * zoom, sin(phi) * zoom, sin(theta) * cos(phi) * zoom);
    
    let targetPos = vec3<f32>(0.0);
    let camForward = normalize(targetPos - camPos);
    let camRight = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), camForward));
    let camUp = cross(camForward, camRight);
    let rd = normalize(uv.x * camRight + uv.y * camUp + 1.5 * camForward);
    
    var t = 0.0;
    var hit = false;
    var id = 0.0;
    
    for (var i: i32 = 0; i < 80; i = i + 1) {
        let pos = camPos + rd * t;
        let de = bismuthDE(pos, time, bass);
        
        if (de.x < 0.001) {
            hit = true;
            id = de.y;
            break;
        }
        
        t += de.x;
        if (t > 10.0) { break; }
    }
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = inputColor.rgb;
    var finalAlpha = inputColor.a;
    
    if (hit) {
        let pos = camPos + rd * t;
        let normal = calcNormal(pos, time, bass);
        
        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.3));
        let diffuse = max(dot(normal, lightDir), 0.0);
        let specular = pow(max(dot(normal, normalize(lightDir - rd)), 0.0), 64.0);
        
        let thickness = 5.0 + id * 2.0 + mids * 5.0; // Audio-reactive iridescent thickness
        let iridColor = iridescence(thickness, normal, -rd);
        
        let shadedColor = iridColor * (diffuse + 0.2) + vec3<f32>(1.0) * specular;
        let hitAlpha = 1.0 - smoothstep(5.0, 10.0, t);
        
        finalRGB = mix(inputColor.rgb, shadedColor, hitAlpha);
        finalAlpha = max(inputColor.a, hitAlpha);
    }
    
    // Temporal Trails
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uvFull, 0.0).rgb;
    finalRGB = mix(finalRGB, prevColor, 0.6);
    
    finalRGB = finalRGB / (1.0 + finalRGB * 0.5); // ACES approx
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, finalAlpha));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha));
}
