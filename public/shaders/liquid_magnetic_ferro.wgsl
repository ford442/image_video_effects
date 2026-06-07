// ═══════════════════════════════════════════════════════════════════════════════
//  liquid_magnetic_ferro.wgsl - Magnetic Ferrofluid Simulation
//  
//  Agent: Interactivist + Algorithmist
//  Techniques:
//    - Magnetic field line simulation
//    - Ferrofluid spike formation (Rosensweig instability)
//    - Mouse-attracted fluid dynamics
//    - Audio-reactive field strength
//  
//  Target: 4.7★ rating
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

// Magnetic dipole field
fn magneticField(p: vec2<f32>, dipolePos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = p - dipolePos;
    let dist2 = dot(d, d);
    let dist = sqrt(dist2);
    
    // Dipole field falls off as 1/r^3
    let magnitude = strength / (dist2 * dist + 0.001);
    
    // Field lines curl around
    return vec2<f32>(
        d.x * magnitude,
        -d.y * magnitude * 0.5
    );
}

// Multiple magnetic sources
fn multiMagneticField(p: vec2<f32>, time: f32, mousePos: vec2<f32>, numDipoles: i32) -> vec2<f32> {
    var field = vec2<f32>(0.0);
    
    // Mouse-controlled dipole
    field += magneticField(p, mousePos, 2.0);
    
    // Orbiting dipoles
    for (var i: i32 = 0; i < numDipoles; i = i + 1) {
        let fi = f32(i);
        let angle = time * 0.5 + fi * (2.0 * PI / f32(numDipoles));
        let radius = 0.3 + sin(time * 0.3 + fi) * 0.1;
        let dipolePos = vec2<f32>(
            0.5 + cos(angle) * radius,
            0.5 + sin(angle) * radius
        );
        field += magneticField(p, dipolePos, 0.8);
    }
    
    return field;
}

// Rosensweig instability - ferrofluid spike formation
fn ferrofluidSpikes(p: vec2<f32>, field: vec2<f32>, time: f32) -> f32 {
    let fieldStrength = length(field);
    let fieldDir = normalize(field);
    
    // Peaks form perpendicular to field lines
    let perp = vec2<f32>(-fieldDir.y, fieldDir.x);
    let alignment = dot(normalize(p - 0.5), perp);
    
    // Instability creates regular pattern
    let pattern = sin(alignment * 20.0 + time) * 
                  cos(fieldStrength * 10.0);
    
    // Sharp peaks
    let spikes = pow(abs(pattern), 0.3) * sign(pattern);
    
    return spikes * fieldStrength;
}

// Metallic iridescent coloring
fn metallicColor(normal: vec2<f32>, lightDir: vec2<f32>, viewDir: vec2<f32>, baseColor: vec3<f32>) -> vec3<f32> {
    // Fresnel
    let fresnel = pow(1.0 - abs(dot(normal, viewDir)), 3.0);
    
    // Specular
    let halfDir = normalize(lightDir + viewDir);
    let specAngle = max(dot(normal, halfDir), 0.0);
    let specular = pow(specAngle, 64.0);
    
    // Iridescent shift
    let shift = dot(normal, lightDir) * 0.5 + 0.5;
    let irid = vec3<f32>(
        sin(shift * PI) * 0.5 + 0.5,
        sin(shift * PI + 2.0) * 0.5 + 0.5,
        sin(shift * PI + 4.0) * 0.5 + 0.5
    );
    
    return baseColor * (0.3 + fresnel * 0.7) + specular * irid * 0.8;
}

// Tone mapping
fn toneMap(x: vec3<f32>) -> vec3<f32> {
    return x / (1.0 + x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let fieldStrength = 0.5 + u.zoom_params.x;         // 0.5-1.5
    let spikeSharpness = u.zoom_params.y * 2.0 + 0.5;  // 0.5-2.5
    let fluidViscosity = u.zoom_params.z;              // 0-1
    let numDipoles = i32(u.zoom_params.w * 4.0) + 2;   // 2-6
    
    // Mouse position (normalized)
    let mousePos = u.zoom_config.yz;
    
    // Audio reactivity
    let audioPulse = u.zoom_config.w;
    
    // Calculate magnetic field
    var field = multiMagneticField(uv, time, mousePos, numDipoles);
    field *= fieldStrength * (1.0 + audioPulse);
    
    // Ferrofluid surface
    let spikes = ferrofluidSpikes(uv, field, time);
    
    // Smooth fluid base
    let fluidBase = smoothstep(0.3, 0.7, length(field));
    
    // Combine
    let height = fluidBase + spikes * spikeSharpness * 0.3;
    
    // Normal from field gradient
    let delta = 0.01;
    let fieldR = multiMagneticField(uv + vec2<f32>(delta, 0.0), time, mousePos, numDipoles);
    let fieldU = multiMagneticField(uv + vec2<f32>(0.0, delta), time, mousePos, numDipoles);
    let normal = normalize(vec2<f32>(
        length(field) - length(fieldR),
        length(field) - length(fieldU)
    ));
    
    // Metallic coloring
    let lightDir = normalize(vec2<f32>(cos(time * 0.5), sin(time * 0.5)));
    let viewDir = normalize(uv - 0.5);
    let baseColor = vec3<f32>(0.1, 0.15, 0.25); // Dark metallic base
    
    var color = metallicColor(normal, lightDir, viewDir, baseColor);
    
    // Highlight peaks
    color += vec3<f32>(1.0, 0.9, 0.7) * max(spikes, 0.0) * 0.5;
    
    // Field line visualization
    let fieldDir = normalize(field);
    let linePattern = abs(sin(atan2(fieldDir.y, fieldDir.x) * 10.0 + time));
    color += vec3<f32>(0.2, 0.4, 0.8) * smoothstep(0.8, 1.0, linePattern) * 0.3;
    
    // Tone mapping
    color = toneMap(color * 2.0);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    color *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(height, 0.0, 0.0, 1.0));
}
