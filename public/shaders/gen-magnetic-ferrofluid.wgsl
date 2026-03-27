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
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=SpikeHeight, y=Density, z=Speed, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Pseudo-random and Noise functions
// ... (hash33, snoise, etc.) ...

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// --- SDFs ---

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// --- Map Function ---

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let time = u.config.x * u.zoom_params.z; // Speed control

    // Base fluid mass
    var d = sdSphere(pos, 1.5);

    // Magnetic spikes displacement
    let spikeDensity = u.zoom_params.y * 5.0 + 1.0;
    let spikeHeight = u.zoom_params.x * 0.5 + 0.1;

    // Use noise to generate spiky perturbations based on direction
    var dir = normalize(pos);
    // (A more complex noise function or mathematical formula for spikes will go here)
    // E.g., combining multiple sine waves or using 3D noise mapped to the sphere surface
    let spikeDisplacement = sin(spikeDensity * pos.x) * sin(spikeDensity * pos.y) * sin(spikeDensity * pos.z) * spikeHeight;

    // Add time-based oscillation to the spikes
    let oscillation = sin(time + length(pos) * 4.0) * 0.5 + 0.5;

    d += spikeDisplacement * oscillation;

    // Optional: Add smaller orbiting fluid droplets that merge smoothly
    let dropletPos = vec3<f32>(sin(time)*2.0, cos(time*1.3)*1.5, sin(time*0.8)*2.0);
    let d2 = sdSphere(pos - dropletPos, 0.4);

    d = smin(d, d2, 0.5); // Smoothly blend droplets into the main mass

    return vec2<f32>(d, 1.0); // ID 1.0 for ferrofluid material
}

// --- Lighting & Rendering ---

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    var uv = (fragCoord * 2.0 - dims) / dims.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    // Mouse interaction for camera orbit
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;

    let temp_ro_yz = rot(mouseY * 1.5) * ro.yz;
    ro.y = temp_ro_yz.x;
    ro.z = temp_ro_yz.y;

    let temp_ro_xz = rot(mouseX * 3.14 + u.config.x * 0.2) * ro.xz;
    ro.x = temp_ro_xz.x;
    ro.z = temp_ro_xz.y;


    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.05, 0.05, 0.08); // Background color

    if (t < 20.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting setup
        let lig = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let hal = normalize(lig - rd);

        let dif = clamp(dot(n, lig), 0.0, 1.0);
        let spec = pow(clamp(dot(n, hal), 0.0, 1.0), 64.0);
        let fre = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 5.0);

        // Base dark metal color
        var matCol = vec3<f32>(0.1, 0.1, 0.15);

        // Iridescence based on viewing angle and color shift parameter
        let iriPhase = dot(n, rd) * 3.14 + u.zoom_params.w * 5.0;
        let iriCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(iriPhase) + vec3<f32>(0.0, 2.0, 4.0));

        matCol = mix(matCol, iriCol, vec3<f32>(fre * 0.5));

        col = matCol * dif * 2.0 + vec3<f32>(1.0) * spec * 2.0 + matCol * fre * 1.0;

        // Add fake environment reflection (simple gradient mapping)
        let refl = reflect(rd, n);
        let envCol = mix(vec3<f32>(0.1, 0.2, 0.3), vec3<f32>(0.8, 0.9, 1.0), refl.y * 0.5 + 0.5);
        col += envCol * matCol * 0.8;
    }

    // Subtle vignette
    col = col * (1.0 - 0.2 * length(uv));

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<u32>(id.xy), vec4<f32>(col, 1.0));
}
