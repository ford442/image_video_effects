// ═══════════════════════════════════════════════════════════════════════════════
//  Lamb-Oseen Vortex Fluid with Kelvin-Helmholtz Shear Instability
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: High
//  Scientific: Lamb-Oseen vortex u_θ = (Γ/2πr)(1−exp(−r²/4νt)),
//              Kelvin-Helmholtz instability at vortex boundary,
//              multiple interacting vortices from ripple history,
//              streamline color coding by velocity magnitude + vorticity
//  Upgraded: Phase B
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,  // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Circulation, y=Viscosity, z=KHAmplitude, w=Aberration
    ripples:     array<vec4<f32>, 50>,
}

// Lamb-Oseen azimuthal velocity: u_θ = Γ/(2πr) · (1 − exp(−r²/(4νt)))
fn lambOseen(p: vec2<f32>, center: vec2<f32>, circulation: f32, nu: f32, age: f32) -> vec2<f32> {
    let d    = p - center;
    let r    = length(d);
    if (r < 0.0001) { return vec2<f32>(0.0); }
    let r2   = r * r;
    let t    = max(age, 0.001);
    // Azimuthal velocity magnitude
    let uTheta = (circulation / (6.28318 * r)) * (1.0 - exp(-r2 / (4.0 * nu * t)));
    // Tangential direction (perpendicular to radial)
    let tangent = vec2<f32>(-d.y, d.x) / r;
    return tangent * uTheta;
}

// Kelvin-Helmholtz sinusoidal perturbation at shear radius
fn khPerturbation(p: vec2<f32>, center: vec2<f32>, shearR: f32, amplitude: f32, time: f32) -> vec2<f32> {
    let d  = p - center;
    let r  = length(d);
    // KH instability is strongest at the viscous core radius
    let envelope = exp(-abs(r - shearR) * abs(r - shearR) / (shearR * shearR * 0.1));
    let angle    = atan2(d.y, d.x);
    // Sinusoidal instability at azimuthal wavenumber m=6
    let perturb  = amplitude * envelope * sin(angle * 6.0 + time * 3.0) * 0.01;
    return normalize(d + vec2<f32>(0.0001)) * perturb;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass   = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    let circulation = mix(-8.0, 8.0, u.zoom_params.x);  // Γ, signed (CW vs CCW)
    let nu          = mix(0.0005, 0.02, u.zoom_params.y); // kinematic viscosity
    let khAmp       = mix(0.0, 1.0, u.zoom_params.z) * (1.0 + bass * 0.5);
    let aberration  = u.zoom_params.w * 0.03;

    var p = vec2<f32>(uv.x * aspect, uv.y);

    // ─── Sum velocity from all active vortices (ripple history) ───
    var vel      = vec2<f32>(0.0);
    var vorticity = 0.0;
    let numV     = min(i32(u.config.y), 20);   // cap at 20 vortices for performance

    // Always include mouse vortex
    var mouseCenter = u.zoom_config.yz;
    mouseCenter.x *= aspect;
    let mouseV = lambOseen(p, mouseCenter, circulation * (1.0 + bass * 0.3), nu, time * 0.1 + 0.001);
    vel += mouseV;
    // KH instability at viscous core
    let coreR = sqrt(4.0 * nu * max(time * 0.1, 0.001));
    vel += khPerturbation(p, mouseCenter, coreR, khAmp, time);

    for (var i = 0; i < 20; i++) {
        if (i >= numV) { break; }
        let rip = u.ripples[i];
        let src = vec2<f32>(rip.x * aspect, rip.y);
        let age = time - rip.z;
        if (age < 0.0 || age > 6.0) { continue; }
        // Alternate CW / CCW for visual variety
        let circ = circulation * select(-0.6, 0.6, (i & 1) == 0) * exp(-age * 0.3);
        vel += lambOseen(p, src, circ, nu, age + 0.001);
        let vcore = sqrt(4.0 * nu * (age + 0.001));
        vel += khPerturbation(p, src, vcore, khAmp * exp(-age * 0.4), time);
    }

    // Approximate vorticity: ω ≈ |∇×v| from circulation strength
    vorticity = length(vel) * sign(circulation);

    // ─── Displace sample UV ───
    let speed  = length(vel);
    // Chromatic aberration by velocity magnitude
    let uvBase = uv - vec2<f32>(vel.x / aspect, vel.y) * 0.04;
    let uvR    = uvBase + vec2<f32>(aberration, 0.0);
    let uvB    = uvBase - vec2<f32>(aberration, 0.0);

    let sR  = textureSampleLevel(readTexture, u_sampler, clamp(uvR, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    let sG  = textureSampleLevel(readTexture, u_sampler, clamp(uvBase, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    let sB  = textureSampleLevel(readTexture, u_sampler, clamp(uvB, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // ─── Vorticity color overlay ───
    // Red = CW vortex, Blue = CCW, Green = irrotational
    let vNorm = clamp(vorticity, -1.0, 1.0);
    let vCol  = mix(
        mix(vec3<f32>(0.1, 0.3, 1.0), vec3<f32>(0.0, 0.8, 0.3), 0.5 + vNorm * 0.5),
        vec3<f32>(1.0, 0.15, 0.05),
        clamp(vNorm, 0.0, 1.0)
    );
    let vIntensity = smoothstep(0.0, 0.5, speed) * 0.35;
    color = mix(color, vCol, vIntensity);

    // Streamline brightness at high-speed regions
    color += vec3<f32>(1.0, 0.8, 0.5) * clamp(speed - 0.3, 0.0, 0.5) * 0.4;

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthUncertainty = speed * 0.08;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel.x, vel.y, vorticity, speed));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
        vec4<f32>(d * (1.0 + depthUncertainty), 0.0, 0.0, 0.0));
}

