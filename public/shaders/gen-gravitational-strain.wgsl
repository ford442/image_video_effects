// ═══════════════════════════════════════════════════════════════════════════════
//  Gravitational Strain Field
//  Category: GENERATIVE | Complexity: VERY_HIGH
//  Invisible gravity wells warp space itself. Space curvature rendered as
//  visual distortion, with emission where fields collide. Dark matter
//  visualization as art—seeing the unseeable.
//  Mathematical approach: N-body gravitational field with Schwarzschild-like
//  metric distortion, geodesic ray tracing through curved spacetime,
//  tidal strain tensor visualization (eigenvalue coloring), gravitational
//  wave emission at merger events, accretion disk glow.
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
    zoom_config: vec4<f32>,  // x=WellCount, y=MouseX, z=MouseY, w=WaveAmplitude
    zoom_params: vec4<f32>,  // x=FieldStrength, y=StrainVis, z=AccretionGlow, w=OrbitSpeed
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Hash functions
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, vec2<f32>(269.5, 183.3))) * 43758.5453)
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Noise for background nebula
// ─────────────────────────────────────────────────────────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var freq = 1.0;
    for (var i = 0; i < 5; i++) {
        v += a * valueNoise(p * freq);
        a *= 0.5; freq *= 2.0;
    }
    return v;
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
//  Gravity well positions (orbiting each other)
// ─────────────────────────────────────────────────────────────────────────────
fn wellPosition(idx: i32, time: f32, orbitSpeed: f32) -> vec3<f32> {
    let fi = f32(idx);
    let seed = vec2<f32>(fi * 17.3, fi * 31.7 + 5.0);
    let basePos = (hash22(seed) * 2.0 - 1.0) * 1.5;

    // Orbit around center of mass
    let phase = time * orbitSpeed * (0.3 + fi * 0.15) + fi * 1.57;
    let orbitR = 0.5 + fi * 0.3;
    let pos = vec2<f32>(
        basePos.x * 0.3 + orbitR * cos(phase),
        basePos.y * 0.3 + orbitR * sin(phase * 0.7 + fi)
    );

    // Mass varies per well
    let mass = 0.5 + hash21(seed + 100.0) * 1.5;

    return vec3<f32>(pos, mass);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compute gravitational field and tidal strain at a point
//  Returns: (deflection.xy, potential, strain_magnitude)
// ─────────────────────────────────────────────────────────────────────────────
fn gravField(p: vec2<f32>, time: f32, numWells: i32, fieldStr: f32, orbitSpeed: f32) -> vec4<f32> {
    var totalDeflection = vec2<f32>(0.0);
    var totalPotential = 0.0;
    var strainMag = 0.0;

    for (var i = 0; i < 8; i++) {
        if (i >= numWells) { break; }
        let well = wellPosition(i, time, orbitSpeed);
        let wellPos = well.xy;
        let mass = well.z;

        let diff = p - wellPos;
        let dist = length(diff) + 0.05; // softening
        let dir = diff / dist;

        // Gravitational deflection (like gravitational lensing)
        let strength = mass * fieldStr / (dist * dist);
        totalDeflection -= dir * strength;

        // Newtonian potential
        totalPotential -= mass / dist;

        // Tidal strain: second derivative of potential
        // Strain ~ mass / r³ (tidal force)
        strainMag += mass / (dist * dist * dist);
    }

    return vec4<f32>(totalDeflection, totalPotential, strainMag);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gravitational wave pattern
//  Simulates the "+" and "×" polarization modes
// ─────────────────────────────────────────────────────────────────────────────
fn gravWave(p: vec2<f32>, time: f32, amplitude: f32) -> f32 {
    var wave = 0.0;
    // Multiple wave sources (from orbiting pairs)
    for (var i = 0; i < 3; i++) {
        let fi = f32(i);
        let freq = 2.0 + fi * 1.5;
        let phase = time * freq + fi * 2.09;
        let waveDir = vec2<f32>(cos(fi * 1.2), sin(fi * 1.2));

        // Plus polarization
        let hPlus = sin(dot(p, waveDir) * 8.0 - phase);
        // Cross polarization
        let hCross = sin(dot(p, vec2<f32>(-waveDir.y, waveDir.x)) * 8.0 - phase + 1.57);

        let r = length(p);
        let decay = amplitude / (r + 0.5);
        wave += (hPlus + hCross * 0.5) * decay;
    }
    return wave;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = (fragCoord * 2.0 - dims) / dims.y;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let fieldStr = u.zoom_params.x * 0.08 + 0.01;          // 0.01 – 0.09
    let strainVis = u.zoom_params.y * 2.0 + 0.3;           // 0.3 – 2.3
    let accretionGlow = u.zoom_params.z * 1.5 + 0.2;       // 0.2 – 1.7
    let orbitSpeed = u.zoom_params.w * 1.5 + 0.2;          // 0.2 – 1.7
    let numWells = i32(u.zoom_config.x * 5.0 + 3.0);       // 3 – 8
    let waveAmp = u.zoom_config.w * 0.5 + 0.05;            // 0.05 – 0.55

    // Mouse adds an extra gravity well
    let mouseUV = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / dims * 2.0 - 1.0);

    // ─────────────────────────────────────────────────────────────────────────
    //  Background: starfield + nebula (this is what gets lensed)
    // ─────────────────────────────────────────────────────────────────────────
    var bgUV = uv;

    // Apply gravitational lensing to background UV
    let field = gravField(uv, time, numWells, fieldStr, orbitSpeed);
    let deflection = field.xy;
    let potential = field.z;
    let strain = field.w;

    // Mouse gravity well
    let mouseDiff = uv - mouseUV;
    let mouseDist = length(mouseDiff) + 0.1;
    let mouseDeflect = -normalize(mouseDiff) * 0.02 / (mouseDist * mouseDist);

    bgUV = uv + deflection + mouseDeflect;

    // Gravitational wave distortion
    let gWave = gravWave(uv, time, waveAmp);
    bgUV += vec2<f32>(gWave * 0.01, gWave * 0.01);

    // Stars
    let starField = pow(hash21(floor(bgUV * 150.0)), 30.0);
    let starColor = vec3<f32>(0.9, 0.95, 1.0) * starField;

    // Nebula
    let nebulaR = fbm(bgUV * 2.0 + time * 0.02);
    let nebulaG = fbm(bgUV * 2.0 + 10.0 + time * 0.015);
    let nebulaB = fbm(bgUV * 2.0 + 20.0 + time * 0.025);
    let nebula = vec3<f32>(nebulaR * 0.15, nebulaG * 0.1, nebulaB * 0.2);

    var col = starColor + nebula + vec3<f32>(0.005, 0.008, 0.015);

    // ─────────────────────────────────────────────────────────────────────────
    //  Tidal strain visualization: color-code the strain tensor
    // ─────────────────────────────────────────────────────────────────────────
    let strainNorm = strain * strainVis;
    let strainColor = hsv2rgb(
        fract(0.6 - strainNorm * 0.5), // Blue (weak) → Red (strong)
        0.7,
        min(strainNorm * 0.8, 0.6)
    );
    col += strainColor;

    // Strain field lines (visualize gradient direction)
    let eps = 0.01;
    let fieldR = gravField(uv + vec2<f32>(eps, 0.0), time, numWells, fieldStr, orbitSpeed).w;
    let fieldL = gravField(uv - vec2<f32>(eps, 0.0), time, numWells, fieldStr, orbitSpeed).w;
    let fieldU = gravField(uv + vec2<f32>(0.0, eps), time, numWells, fieldStr, orbitSpeed).w;
    let fieldD = gravField(uv - vec2<f32>(0.0, eps), time, numWells, fieldStr, orbitSpeed).w;
    let strainGrad = vec2<f32>(fieldR - fieldL, fieldU - fieldD);
    let strainLines = abs(sin(atan2(strainGrad.y, strainGrad.x) * 8.0 + length(strainGrad) * 50.0));
    col += vec3<f32>(0.1, 0.15, 0.3) * smoothstep(0.95, 1.0, strainLines) * strainNorm * 0.5;

    // ─────────────────────────────────────────────────────────────────────────
    //  Accretion disks around gravity wells
    // ─────────────────────────────────────────────────────────────────────────
    for (var i = 0; i < 8; i++) {
        if (i >= numWells) { break; }
        let well = wellPosition(i, time, orbitSpeed);
        let wellPos = well.xy;
        let mass = well.z;

        let diff = uv - wellPos;
        let dist = length(diff);

        // Accretion ring
        let ringRadius = mass * 0.15;
        let ringWidth = 0.04;
        let ring = exp(-pow((dist - ringRadius) / ringWidth, 2.0));

        // Rotation pattern
        let angle = atan2(diff.y, diff.x);
        let spiral = sin(angle * 3.0 - time * 4.0 * orbitSpeed - dist * 20.0) * 0.5 + 0.5;

        let diskHue = fract(0.05 + dist * 2.0); // Red-orange-yellow
        let diskColor = hsv2rgb(diskHue, 0.8, 1.0);
        col += diskColor * ring * spiral * accretionGlow * mass;

        // Event horizon glow
        let horizonGlow = exp(-dist * 15.0 / mass) * mass * 0.2;
        col += vec3<f32>(0.1, 0.05, 0.2) * horizonGlow * accretionGlow;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Gravitational wave visualization
    // ─────────────────────────────────────────────────────────────────────────
    let waveVis = abs(gWave);
    let waveColor = hsv2rgb(fract(0.5 + gWave * 0.5), 0.6, waveVis * 0.3);
    col += waveColor * waveAmp * 2.0;

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: create temporary gravity sources
    // ─────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let rUV = (r.xy * 2.0 - 1.0);
        let dist = length(uv - rUV);
        let age = time - r.z;
        if (age > 0.0 && age < 5.0) {
            // Merger event: expanding gravitational wave front
            let waveFront = exp(-abs(dist - age * 0.6) * 12.0) * exp(-age * 0.4);
            let mergerColor = hsv2rgb(fract(dist * 2.0 + 0.6), 0.7, 1.0);
            col += mergerColor * waveFront * 0.5;

            // Central flash (merger moment)
            let flash = exp(-dist * 8.0) * exp(-age * 3.0);
            col += vec3<f32>(1.0, 0.8, 0.5) * flash;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Vignette and tone mapping
    // ─────────────────────────────────────────────────────────────────────────
    col *= 1.0 - 0.3 * dot(uv, uv) * 0.25;
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
