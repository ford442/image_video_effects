// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var <uniform> u: Uniforms;
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
  zoom_config: vec4<f32>,  // x=ZoomTime
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=DiskWidth, w=Redshift
  ripples: array<vec4<f32>, 50>,
};

// Smoothstep alternative with more control
fn smoothstep_edge(a: f32, b: f32, x: f32) -> f32 {
    let t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters from sliders
    let strength = mix(0.2, 2.0, u.zoom_params.x);      // Mass/gravity strength
    let eventHorizon = u.zoom_params.y * 0.15;          // Schwarzschild radius
    let diskWidth = mix(0.05, 0.3, u.zoom_params.z);    // Accretion disk thickness
    let redshiftIntensity = u.zoom_params.w;            // Gravitational redshift

    var totalDisplacement = vec2<f32>(0.0);
    var blackHoleMask = 0.0;      // For event horizon
    var diskMask = 0.0;           // For accretion disk
    var einsteinRadius = 0.0;     // For photon ring
    var activeCenter = vec2<f32>(0.5);

    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let center = ripple.xy;
        let age = time - ripple.z;

        // Black holes last 5 seconds with smooth fade
        if (age > 0.0 && age < 5.0) {
            activeCenter = center;
            let dVec = uv - center;
            
            // Correct for aspect ratio for perfect circles
            let aspect = resolution.x / resolution.y;
            let dVecAspect = dVec * vec2<f32>(aspect, 1.0);
            let dist = length(dVecAspect);
            
            // Lifetime fade (ease out)
            let lifetimeFade = 1.0 - smoothstep_edge(3.5, 5.0, age);
            
            // --- Gravitational Lensing ---
            // Einstein radius approximation: sqrt(4GM/c² * d_ls / (d_l * d_s))
            // We simplify to: strength / distance for the deflection angle
            let deflectionAngle = strength * lifetimeFade / max(dist - eventHorizon * 0.5, 0.001);
            
            // Pull UVs towards center (gravitational attraction)
            totalDisplacement -= normalize(dVec) * deflectionAngle * 0.03;

            // --- Event Horizon Detection ---
            if (dist < eventHorizon) {
                blackHoleMask = 1.0;
            }
            
            // --- Accretion Disk ---
            // Disk is a ring around the black hole
            let diskInner = eventHorizon * 1.5;  // Innermost Stable Circular Orbit (ISCO)
            let diskOuter = eventHorizon + diskWidth;
            
            if (dist >= diskInner && dist <= diskOuter) {
                diskMask = 1.0 - smoothstep_edge(diskInner, diskOuter, dist);
            }
            
            // --- Photon Ring (Inner Bright Edge) ---
            // Light that orbited the black hole before escaping
            let photonRingRadius = eventHorizon * 1.5;
            if (dist > photonRingRadius * 0.9 && dist < photonRingRadius * 1.1) {
                einsteinRadius = 1.0 - smoothstep_edge(photonRingRadius * 0.9, photonRingRadius * 1.1, dist);
            }
        }
    }

    let finalUV = uv + totalDisplacement;
    
    // Sample texture with high-quality filtering
    var color = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    // --- Gravitational Effects on Color ---
    
    // 1. Brightness Amplification (gravitational lensing magnification)
    let magnification = length(totalDisplacement) * 2.0 + 1.0;
    color = vec4<f32>(color.rgb * mix(1.0, magnification, 0.3), color.a);
    
    // 2. Gravitational Redshift (light loses energy climbing out of gravity well)
    if (redshiftIntensity > 0.01) {
        let redshift = 1.0 - (length(totalDisplacement) * redshiftIntensity * 0.5);
        color = vec4<f32>(color.r, color.g * redshift, color.b * redshift * redshift, color.a);
    }
    
    // 3. Accretion Disk Rendering
    if (diskMask > 0.01) {
        // Temperature gradient: hot (white/blue) near center, cooler (red) outside
        let tempT = smoothstep_edge(eventHorizon * 1.5, eventHorizon + diskWidth, length(uv - activeCenter));
        let diskColor = mix(vec3<f32>(1.0, 0.3, 0.0), vec3<f32>(1.0, 1.0, 0.8), tempT);
        
        // Add turbulence/flicker
        let flicker = sin(time * 50.0 + length(uv) * 100.0) * 0.1 + 0.9;
        
        color = vec4<f32>(mix(color.rgb, diskColor * flicker, diskMask * 0.8), color.a);
    }
    
    // 4. Photon Ring (bright inner edge)
    if (einsteinRadius > 0.01) {
        color = vec4<f32>(color.rgb + vec3<f32>(1.0, 0.8, 0.5) * einsteinRadius * 2.0, color.a);
    }
    
    // 5. Event Horizon (black center)
    if (blackHoleMask > 0.5) {
        color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth with slight displacement for 3D effect
    let depthUV = clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
