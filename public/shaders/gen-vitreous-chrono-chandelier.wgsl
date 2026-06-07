// ----------------------------------------------------------------
// Vitreous Chrono-Chandelier
// Category: generative
// ----------------------------------------------------------------
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission
    ripples: array<vec4<f32>, 50>,
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdRoundedBox(p: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

fn pendulumAngle(theta0: f32, t: f32, length: f32, damping: f32) -> f32 {
    let g = 9.81;
    let omega = sqrt(g / length);
    let dampedAmp = theta0 * exp(-damping * t);
    return dampedAmp * cos(omega * t);
}

fn refractRay(rd: vec3<f32>, n: vec3<f32>, ior: f32) -> vec3<f32> {
    let dt = dot(rd, n);
    let discr = 1.0 - ior * ior * (1.0 - dt * dt);
    if (discr < 0.0) { return reflect(rd, n); }
    return ior * rd - (ior * dt + sqrt(discr)) * n;
}

fn causticPattern(p: vec3<f32>, time: f32) -> f32 {
    let s1 = sin(p.x * 8.0 + time * 2.0);
    let s2 = sin(p.y * 7.0 - time * 1.5);
    let s3 = sin(p.z * 6.0 + time * 1.0);
    return abs(s1 * s2 * s3);
}

fn fresnelSchlick(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    let ct = clamp(1.0 - cosTheta, 0.0, 1.0);
    let ct5 = ct * ct * ct * ct * ct;
    return F0 + (vec3<f32>(1.0) - F0) * ct5;
}

fn sceneSDF(p: vec3<f32>, time: f32, chimeDensity: f32, audioBass: f32) -> f32 {
    var q = p;
    let cellX = round(q.x / chimeDensity);
    let cellZ = round(q.z / chimeDensity);
    q.x = q.x - cellX * chimeDensity;
    q.z = q.z - cellZ * chimeDensity;
    let h = hash3(vec3<f32>(cellX, 0.0, cellZ));
    let len = 1.0 + h.x * 2.0;
    let damping = 0.1 + h.y * 0.2;
    let theta0 = 0.3 + h.z * 0.4;
    let angle = pendulumAngle(theta0, time + cellX * 0.5 + cellZ * 0.3, len, damping);
    let swingX = sin(angle) * len;
    let swingZ = cos(angle) * len * 0.3;
    var crystalPos = q - vec3<f32>(swingX, -1.5, swingZ);
    let crystal = sdRoundedBox(crystalPos, vec3<f32>(0.25, 0.6, 0.15), 0.05);
    var mountPos = q - vec3<f32>(0.0, 0.8, 0.0);
    let mount = sdTorus(mountPos, vec2<f32>(0.3, 0.06));
    let linkBox = sdRoundedBox(q - vec3<f32>(0.0, 0.4, 0.0), vec3<f32>(0.04, 0.15, 0.04), 0.01);
    let d1 = min(crystal, mount);
    let d2 = min(d1, linkBox);
    return d2 - audioBass * 0.02;
}

fn calcNormal(p: vec3<f32>, time: f32, chimeDensity: f32, audioBass: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * sceneSDF(p + e.xyy, time, chimeDensity, audioBass) +
                     e.yyx * sceneSDF(p + e.yyx, time, chimeDensity, audioBass) +
                     e.yxy * sceneSDF(p + e.yxy, time, chimeDensity, audioBass) +
                     e.xxx * sceneSDF(p + e.xxx, time, chimeDensity, audioBass));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }
    let uv = (fragCoord * 2.0 - res) / res.y;
    let shatterThreshold = u.zoom_params.x;
    let chimeDensity = u.zoom_params.y;
    let refractionIndex = u.zoom_params.z;
    let transmission = u.zoom_params.w;
    let audioBass = plasmaBuffer[0].x;
    let time = u.config.x * 0.5;
    var ro = vec3<f32>(0.0, 3.0, -8.0);
    var rd = normalize(vec3<f32>(uv, 1.0));
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
    let mousePos = vec3<f32>(mouseX * 5.0, 3.0 + mouseY * 4.0, 0.0);
    var t = 0.0;
    var hit = false;
    var hitP = vec3<f32>(0.0);
    for(var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        let distToMouse = distance(p, mousePos);
        if (distToMouse < 4.0) {
            p += normalize(p - mousePos) * (1.0 / (distToMouse + 0.5)) * audioBass;
        }
        let d = sceneSDF(p, time, chimeDensity, audioBass);
        if (d < 0.001) {
            hit = true;
            hitP = p;
            break;
        }
        t += d * 0.6;
        if (t > 50.0) { break; }
    }
    var colR = 0.0;
    var colG = 0.0;
    var colB = 0.0;
    var fresnel = vec3<f32>(0.0);
    if (hit) {
        let n = calcNormal(hitP, time, chimeDensity, audioBass);
        let viewDir = -rd;
        let cosTheta = clamp(dot(viewDir, n), 0.0, 1.0);
        let F0 = vec3<f32>(0.04);
        fresnel = fresnelSchlick(cosTheta, F0);
        let iorR = 1.5 + refractionIndex * 0.1;
        let iorG = 1.52 + refractionIndex * 0.1;
        let iorB = 1.54 + refractionIndex * 0.1;
        let rdR = refractRay(rd, n, 1.0 / iorR);
        let rdG = refractRay(rd, n, 1.0 / iorG);
        let rdB = refractRay(rd, n, 1.0 / iorB);
        let causticR = causticPattern(hitP + rdR * 2.0, time);
        let causticG = causticPattern(hitP + rdG * 2.0, time);
        let causticB = causticPattern(hitP + rdB * 2.0, time);
        colR = causticR * 0.8 + fresnel.r * 0.3;
        colG = causticG * 0.7 + fresnel.g * 0.3;
        colB = causticB * 0.6 + fresnel.b * 0.3;
        colR = colR * transmission + audioBass * 0.1;
        colG = colG * transmission + audioBass * 0.05;
        colB = colB * transmission;
    } else {
        let bgGlow = vec3<f32>(0.05, 0.02, 0.08) * (1.0 - length(uv) * 0.5);
        colR = bgGlow.r;
        colG = bgGlow.g;
        colB = bgGlow.b;
    }
    colR = clamp(colR, 0.0, 1.0);
    colG = clamp(colG, 0.0, 1.0);
    colB = clamp(colB, 0.0, 1.0);
    let alpha = clamp(fresnel.r * 0.8 + 0.2, 0.0, 1.0);
    let uv01 = fragCoord / res;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(colR, colG, colB, alpha));
}
