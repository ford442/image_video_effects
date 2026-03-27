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
    zoom_params: vec4<f32>,  // x=RotationSpeed, y=Complexity, z=RingScale, w=CoreIntensity
    ripples: array<vec4<f32>, 50>,
};

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Rotation around X axis
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, c, -s,
        0.0, s, c
    );
}

// Rotation around Y axis
fn rotY(a: f32) -> mat3x3<f32> {
    var s = sin(a);
    var c = cos(a);
    return mat3x3<f32>(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

// Rotation around Z axis
fn rotZ(a: f32) -> mat3x3<f32> {
    var s = sin(a);
    var c = cos(a);
    return mat3x3<f32>(
        c, -s, 0.0,
        s, c, 0.0,
        0.0, 0.0, 1.0
    );
}

// Smooth minimum for blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// --- SDFs ---

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    var q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    var q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    var d = vec2<f32>(length(p.xz), p.y) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// --- Noise Functions ---
fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3D(p: vec3<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    var n = i.x + i.y * 157.0 + 113.0 * i.z;
    return mix(
        mix(
            mix(hash31(i + vec3<f32>(0.0, 0.0, 0.0)), hash31(i + vec3<f32>(1.0, 0.0, 0.0)), f.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 0.0)), hash31(i + vec3<f32>(1.0, 1.0, 0.0)), f.x),
            f.y
        ),
        mix(
            mix(hash31(i + vec3<f32>(0.0, 0.0, 1.0)), hash31(i + vec3<f32>(1.0, 0.0, 1.0)), f.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 1.0)), hash31(i + vec3<f32>(1.0, 1.0, 1.0)), f.x),
            f.y
        ),
        f.z
    );
}

// FBM for plasma texture
fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i = 0; i < 4; i++) {
        value += amplitude * noise3D(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// --- Map Function ---
// Returns vec3: x = distance, y = material ID, z = emission
fn map(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    var time = u.config.x;
    let speed = u.zoom_params.x;
    let complexity = u.zoom_params.y;
    let scale = u.zoom_params.z;
    
    var d = 1000.0;
    var mat = 0.0;
    var emission = 0.0;
    
    // --- Central Energy Core (Pulsating Star) ---
    let corePulse = 1.0 + sin(time * 3.0) * 0.1;
    let coreRadius = 0.8 * corePulse * scale;
    let dCore = sdSphere(p, coreRadius);
    
    // Plasma texture on core surface
    let plasmaNoise = fbm(p * 3.0 + time * 0.5);
    let dCorePlasma = dCore - plasmaNoise * 0.1;
    
    if (dCorePlasma < d) {
        d = dCorePlasma;
        mat = 1.0; // Core material
        emission = u.zoom_params.w * (1.0 + plasmaNoise * 0.5);
    }
    
    // --- Contra-Rotating Rings ---
    let numRings = 3 + i32(complexity * 3.0);
    
    for (var i = 0; i < numRings; i++) {
        let fi = f32(i);
        
        // Ring parameters
        let ringRadius = (1.5 + fi * 0.8) * scale;
        let ringThickness = 0.08 + complexity * 0.05;
        
        // Rotation axes for each ring
        let rotSpeed1 = time * speed * (0.5 + fi * 0.2);
        let rotSpeed2 = time * speed * (0.3 - fi * 0.15);
        
        // Transform position for this ring
        var ringP = p;
        
        // Apply contra-rotation
        if (i % 2 == 0) {
            ringP = rotX(rotSpeed1) * ringP;
            ringP = rotY(rotSpeed2 * 0.5) * ringP;
        } else {
            ringP = rotY(rotSpeed1) * ringP;
            ringP = rotZ(rotSpeed2 * 0.7) * ringP;
        }
        
        // Base torus
        let dTorus = sdTorus(ringP, vec2<f32>(ringRadius, ringThickness));
        
        // Boolean trenches/greebles - carve details into rings
        let trenchCount = 6.0 + fi * 4.0;
        let trenchAngle = atan2(ringP.z, ringP.x) * trenchCount + time * speed;
        let trenchPos = vec3<f32>(
            ringRadius * cos(trenchAngle / trenchCount),
            ringP.y,
            ringRadius * sin(trenchAngle / trenchCount)
        );
        let dTrench = sdBox(ringP - trenchPos, vec3<f32>(0.02, 0.15, 0.02) * scale);
        
        // Subtract trenches
        let dRingDetail = max(dTorus, -dTrench);
        
        // Add glowing panels
        let panelCount = 12.0;
        let panelAngle = atan2(ringP.z, ringP.x) * panelCount;
        let panelPhase = sin(panelAngle + time * speed * 2.0);
        let isPanel = panelPhase > 0.7;
        
        if (dRingDetail < d) {
            d = dRingDetail;
            mat = 2.0; // Metal ring material
            if (isPanel) {
                mat = 3.0; // Glowing panel
                emission = 0.5 * u.zoom_params.w;
            }
        }
    }
    
    // --- Plasma Arcs ---
    // Occasional energy bridges between rings and core
    let arcTime = fract(time * 0.3);
    if (arcTime < 0.3) {
        let arcAngle = time * 2.0;
        let arcRadius = 1.2 * scale;
        let arcPos = vec3<f32>(
            arcRadius * cos(arcAngle),
            sin(time * 5.0) * 0.3,
            arcRadius * sin(arcAngle)
        );
        let dArc = sdSphere(p - arcPos, 0.05 * scale * (1.0 - arcTime * 3.0));
        
        if (dArc < d) {
            d = dArc;
            mat = 4.0; // Plasma arc
            emission = 2.0 * u.zoom_params.w * (1.0 - arcTime * 3.0);
        }
    }
    
    return vec3<f32>(d, mat, emission);
}

// --- Normal Calculation ---
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }
    
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    
    // Camera setup
    var time = u.config.x;
    var ro = vec3<f32>(0.0, 0.0, 6.0);
    
    // Mouse interaction for camera orbit
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;
    
    let temp_ro_yz = rot(mouseY * 1.5) * ro.yz;
    ro.y = temp_ro_yz.x;
    ro.z = temp_ro_yz.y;

    let temp_ro_xz = rot(mouseX * 3.14 + time * 0.1) * ro.xz;
    ro.x = temp_ro_xz.x;
    ro.z = temp_ro_xz.y;

    
    // Camera look-at
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.8 * ww);
    
    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var accumEmission = 0.0;
    let maxSteps = 128;
    let maxDist = 30.0;
    
    for (var i = 0; i < maxSteps; i++) {
        var p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        accumEmission += res.z;
        
        if (d < 0.001 || t > maxDist) { break; }
        t += d * 0.6; // Smaller steps for detailed structure
    }
    
    // Space background with subtle nebula
    var col = vec3<f32>(0.005, 0.01, 0.02);
    let nebula = fbm(rd * 2.0 + time * 0.05);
    col += vec3<f32>(0.02, 0.03, 0.05) * nebula * max(0.0, rd.y);
    
    // Add distant stars
    let stars = pow(hash31(rd * 500.0), 20.0);
    col += vec3<f32>(stars);
    
    if (t < maxDist) {
        var p = ro + rd * t;
        var n = calcNormal(p);
        let v = normalize(ro - p);
        
        // Core is the primary light source
        let corePos = vec3<f32>(0.0);
        let toCore = normalize(corePos - p);
        
        // Distance to core for lighting falloff
        let distToCore = length(p);
        let coreIntensity = u.zoom_params.w;
        
        // Material-specific shading
        if (m == 1.0) {
            // --- Core Material (Pulsating Star) ---
            let plasmaDetail = fbm(p * 5.0 + time);
            let coreCol = vec3<f32>(1.0, 0.7, 0.3) * (1.0 + plasmaDetail * 0.3);
            col = coreCol * coreIntensity * 2.0;
            
        } else if (m == 2.0 || m == 3.0) {
            // --- Metal Ring Material ---
            
            // Lighting from core
            let dif = max(dot(n, toCore), 0.0);
            let hal = normalize(toCore - rd);
            let spec = pow(max(dot(n, hal), 0.0), 64.0);
            let fre = pow(1.0 - max(dot(n, v), 0.0), 5.0);
            
            // Metal color with rim lighting from core
            let metalCol = vec3<f32>(0.4, 0.45, 0.5);
            let warmRim = vec3<f32>(1.0, 0.6, 0.3) * fre * coreIntensity;
            
            // Ambient light from core based on distance
            let ambientCore = coreIntensity / (distToCore * distToCore + 1.0);
            
            col = metalCol * (dif * coreIntensity + ambientCore * 0.3);
            col += vec3<f32>(1.0) * spec * coreIntensity;
            col += warmRim;
            
            if (m == 3.0) {
                // Glowing panels
                col += vec3<f32>(0.3, 0.8, 1.0) * 0.5 * coreIntensity;
            }
            
        } else if (m == 4.0) {
            // --- Plasma Arc ---
            col = vec3<f32>(0.5, 0.8, 1.0) * coreIntensity * 3.0;
        }
        
        // Global emission accumulation (glow from core/proximity)
        col += accumEmission * vec3<f32>(0.3, 0.5, 1.0) * 0.05;
        
        // Distance fog (dark space)
        col = mix(col, vec3<f32>(0.005, 0.01, 0.02), 1.0 - exp(-0.08 * t));
    }
    
    // Vignette
    col *= 1.0 - 0.4 * length(uv);
    
    // Tone mapping
    col = col / (col + vec3<f32>(1.0));
    
    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));
    
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
