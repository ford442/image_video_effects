// ═══════════════════════════════════════════════════════════════════
//  Kimi Ripple Touch — Multi-Wave Superposition Interference Field
//  Category: interactive-mouse
//  Features: mouse-driven, interactive, ripple, water, audio-reactive
//  Complexity: High
//  Scientific: All 50 ripple sources summed as coherent wave sources.
//              Huygen's principle — each click spawns a circular wave.
//              Constructive / destructive interference → fringe pattern.
//              Phase velocity, temporal decay, spatial attenuation.
//  Upgraded: Phase B — full wave superposition over entire ripple array
// ═══════════════════════════════════════════════════════════════════

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
    zoom_params: vec4<f32>,  // x=WaveNumber, y=PhaseSpeed, z=Amplitude, w=DecayRate
    ripples:     array<vec4<f32>, 50>,
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coords = vec2<i32>(global_id.xy);

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse    = u.zoom_config.yz;
    let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
    let aspect   = resolution.x / max(resolution.y, 0.001);

    // Wave physics parameters
    let k      = mix(8.0, 40.0, u.zoom_params.x) * (1.0 + treble * 0.3); // wavenumber
    let omega  = mix(2.0, 12.0, u.zoom_params.y) * (1.0 + bass * 0.4);   // angular frequency
    let amp    = mix(0.002, 0.025, u.zoom_params.z);
    let gamma  = mix(0.3, 2.5, u.zoom_params.w);    // temporal damping
    let alpha_r = 1.5;                               // spatial attenuation (1/r spreading)

    var p   = vec2<f32>(uv.x * aspect, uv.y);

    // ─── Sum all 50 ripple sources (Huygens superposition) ───
    let numSources = i32(u.config.y);
    var waveX  = 0.0;  // x-component of total displacement
    var waveY  = 0.0;  // y-component of total displacement
    var energy = 0.0;  // interference energy density

    for (var i = 0; i < 50; i++) {
        if (i >= numSources) { break; }
        let rip   = u.ripples[i];
        let src   = vec2<f32>(rip.x * aspect, rip.y);
        let t0    = rip.z;
        let age   = time - t0;
        if (age < 0.0 || age > 8.0) { continue; }

        let r     = length(p - src);
        // Radial wave packet: only exists where the wavefront has passed
        let waveFront = max(0.0, age * omega / k - r);
        if (waveFront < 0.001) { continue; }

        // Wave amplitude with geometric spreading and temporal decay
        let A = amp * exp(-gamma * age) * exp(-alpha_r * r) / max(sqrt(r * k), 0.1);

        // Phase: φ = k·r − ω·age
        let phase = k * r - omega * age;
        let waveSin = sin(phase) * A;
        let waveCos = cos(phase) * A;

        // Gradient direction (radially outward from source)
        let dir = select(vec2<f32>(1.0, 0.0), normalize(p - src), r > 0.0001);
        waveX += dir.x * waveSin;
        waveY += dir.y * waveSin;
        energy += waveSin * waveSin;
    }

    // Add real-time mouse position wave (continuous while held)
    if (mouseDown > 0.5) {
        let msrc  = vec2<f32>(mouse.x * aspect, mouse.y);
        let mr    = length(p - msrc);
        let mA    = amp * 1.5 * exp(-alpha_r * mr * 0.5) / max(sqrt(mr * k + 0.1), 0.1);
        let mPhase = k * mr - omega * time;
        let mW    = sin(mPhase) * mA;
        let mDir  = select(vec2<f32>(1.0, 0.0), normalize(p - msrc), mr > 0.0001);
        waveX += mDir.x * mW;
        waveY += mDir.y * mW;
        energy += mW * mW;
    }

    // Audio-reactive: bass adds ring pulse from centre
    let centreR = length(p - vec2<f32>(aspect * 0.5, 0.5));
    let audioWave = bass * amp * 2.0 * sin(k * centreR - omega * time * 0.5)
                    * exp(-centreR * 2.0) / max(centreR, 0.05);
    let cDir = select(vec2<f32>(1.0, 0.0), normalize(p - vec2<f32>(aspect * 0.5, 0.5)), centreR > 0.001);
    waveX += cDir.x * audioWave;
    waveY += cDir.y * audioWave;

    // Refraction: displace sample UV by summed gradient
    let dispUV = vec2<f32>(waveX / aspect, waveY);
    let sampUV = clamp(uv + dispUV, vec2<f32>(0.001), vec2<f32>(0.999));

    // Chromatic aberration scales with interference energy
    let caS = min(sqrt(energy) * 0.01, 0.015);
    let cR  = textureSampleLevel(readTexture, u_sampler, clamp(sampUV + vec2<f32>( caS, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let cG  = textureSampleLevel(readTexture, u_sampler, sampUV, 0.0).g;
    let cB  = textureSampleLevel(readTexture, u_sampler, clamp(sampUV - vec2<f32>( caS, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var color = vec3<f32>(cR, cG, cB);

    // Interference fringe overlay: bright at constructive maxima
    let fringeIntensity = clamp(energy * 40.0, 0.0, 1.0);
    // Hue of fringes cycles with interference order (like Newton's rings)
    let fringeOrder = sqrt(energy) * k / (2.0 * 3.14159);
    let fringeHue = fract(fringeOrder * 0.5 + time * 0.05);
    let fringeCol = vec3<f32>(
        0.5 + 0.5 * sin(fringeHue * 6.28318),
        0.5 + 0.5 * sin(fringeHue * 6.28318 + 2.0944),
        0.5 + 0.5 * sin(fringeHue * 6.28318 + 4.1888)
    );
    color += fringeCol * fringeIntensity * 0.6;

    // Depth modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    color *= mix(0.7, 1.0, depth);

    let luma  = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    textureStore(writeTexture, coords, vec4<f32>(color, luma));
    textureStore(dataTextureA, coords, vec4<f32>(waveX, waveY, energy, fringeIntensity));
    textureStore(writeDepthTexture, coords, vec4<f32>(clamp(fringeIntensity * 0.5 + depth * 0.5, 0.0, 1.0), 0.0, 0.0, 0.0));
}

