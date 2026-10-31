// ═══════════════════════════════════════════════════════════════════
//  Predator-Prey RGBA
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12, 2026-10-31
//  Ideas: carnivore pursuit along herbivore gradient; herbivore flee from carnivores; herd surface tension (mean-curvature rounding of herbivore fronts); carrion toxin (deaths + unassimilated kill biomass return as toxin); kill flash from the hunting term; seasonal bloom (Plant Growth swells on a travelling, luminance-shifted phase); dominance-mixed species pigments
//  A packing: raw (plants, herbivores, carnivores, toxin)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn stateAt(coord: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let prevState = stateAt(coord, dims);
    var plants = prevState.r;
    var herbivores = prevState.g;
    var carnivores = prevState.b;
    var toxin = prevState.a;

    if (time < 0.1) {
        plants = 0.0;
        herbivores = 0.0;
        carnivores = 0.0;
        toxin = 0.0;
        let n = hash21(uv * 500.0);
        if (n > 0.85) { plants = 0.6; }
        if (n > 0.95) { herbivores = 0.3; }
        if (n > 0.98) { carnivores = 0.15; }
    }

    plants = clamp(plants, 0.0, 4.0);
    herbivores = clamp(herbivores, 0.0, 4.0);
    carnivores = clamp(carnivores, 0.0, 4.0);
    toxin = clamp(toxin, 0.0, 4.0);

    // HEAD fix: the only seeding was `time < 0.1`, so loading the shader after the first 0.1 s
    // (or after any wipe) left herbivores/carnivores permanently at 0 and the field blank.
    // Rare immigrants now arrive wherever food is present and the species is locally absent.
    // soft immigrant blobs on a coarse grid (one random cell per ~0.5 s bin), not per-pixel specks
    let binT = floor(time * 2.0);
    let gH = floor(uv * 24.0);
    let seedH = hash21(gH + vec2<f32>(binT * 7.0, 3.0));
    let dH = length(uv * 24.0 - gH - vec2<f32>(0.5));
    if (herbivores < 0.02 && plants > 0.2 && seedH < 0.02) { herbivores += 0.25 * exp(-dH * dH * 12.0); }
    let gC = floor(uv * 12.0);
    let seedC = hash21(gC + vec2<f32>(binT * 5.0, 9.0));
    let dC = length(uv * 12.0 - gC - vec2<f32>(0.5));
    if (carnivores < 0.01 && herbivores > 0.15 && seedC < 0.015) { carnivores += 0.18 * exp(-dC * dC * 10.0); }

    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);

    let upLeft = stateAt(coord + vec2<i32>(-1, 1), dims);
    let upRight = stateAt(coord + vec2<i32>(1, 1), dims);
    let downLeft = stateAt(coord + vec2<i32>(-1, -1), dims);
    let downRight = stateAt(coord + vec2<i32>(1, -1), dims);

    let lapP = left.r + right.r + down.r + up.r - 4.0 * plants;
    let lapH = left.g + right.g + down.g + up.g - 4.0 * herbivores;
    let lapC = left.b + right.b + down.b + up.b - 4.0 * carnivores;
    let lapT = left.a + right.a + down.a + up.a - 4.0 * toxin;

    let eatProbability = mix(0.1, 0.5, u.zoom_params.x) * (1.0 + audio.y * 0.2);
    let deathRate = mix(0.001, 0.05, u.zoom_params.y) * (1.0 + audio.x * 0.25);
    let plantGrowth = mix(0.01, 0.05, u.zoom_params.z);
    let toxinStrength = mix(0.4, 1.6, u.zoom_params.w);
    let toxinDecay = 0.95;

    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // HEAD fix: photosynthesis floor, so a dark source no longer starves the whole food chain
    // HEAD fix: logistic growth — at HEAD plants grew unbounded to the 2.0 clamp, which fed herbivores
    // (and then carnivores) to their clamps too: a uniform wash with no herds left to look at.
    // ── Idea 6: seasonal bloom — Plant Growth swells and fades on a phase that travels diagonally and is
    // shifted by the photo's luminance, so growth fronts keep crossing the picture and the herds chase them
    let season = 1.0 + 0.75 * sin(time * 0.6 - dot(uv, vec2<f32>(5.0, 3.0)) + sourceLum * 4.0);
    plants += plantGrowth * season * (0.2 + 0.8 * sourceLum) * max(1.0 - plants * 0.5, 0.0) + lapP * 0.05;

    let grazing = plants * herbivores * eatProbability;
    plants -= grazing;
    herbivores += grazing * 0.5;

    let hunting = herbivores * carnivores * eatProbability * 0.8;
    herbivores -= hunting;
    carnivores += hunting * 0.7;

    // HEAD fix: crowding mortality (quadratic) is the carrying capacity the model never had
    let herbDeaths = herbivores * deathRate * 0.5 + herbivores * herbivores * 0.03;
    let carnDeaths = carnivores * deathRate * 0.5 + carnivores * carnivores * 0.06;
    herbivores -= herbDeaths;
    carnivores -= carnDeaths;

    toxin += (herbivores * herbivores + carnivores * carnivores) * 0.002;
    // ── Idea 3: carrion toxin — bodies and the 30% of a kill the predator cannot assimilate rot into toxin
    toxin += (herbDeaths + carnDeaths + hunting * 0.3) * 0.6;
    toxin += lapT * 0.02;
    toxin *= toxinDecay;

    let toxinKill = toxin * 0.01 * toxinStrength;
    // HEAD fix: toxin killed an ABSOLUTE amount per frame, which erased any species below ~0.004 and
    // made carnivores unable to re-establish; now proportional (rates x5 / x10 / x15 keep the slider's reach)
    plants -= plants * toxinKill * 5.0;
    herbivores -= herbivores * toxinKill * 10.0;
    carnivores -= carnivores * toxinKill * 8.0;

    // ── Idea 4: herd surface tension — mean-curvature flow (phi_xx*phi_y^2 - 2*phi_xy*phi_x*phi_y + phi_yy*phi_x^2)/|grad|^2
    // rounds herd fronts instead of letting plain diffusion smear them
    let hx = (right.g - left.g) * 0.5;
    let hy = (up.g - down.g) * 0.5;
    // old centre value: `herbivores` is already updated in-frame, neighbours are not
    let hxx = right.g + left.g - 2.0 * prevState.g;
    let hyy = up.g + down.g - 2.0 * prevState.g;
    let hxy = (upRight.g - upLeft.g - downRight.g + downLeft.g) * 0.25;
    let curvature = (hxx * hy * hy - 2.0 * hxy * hx * hy + hyy * hx * hx) / (hx * hx + hy * hy + 0.01);
    herbivores += clamp(curvature, -0.5, 0.5) * 0.25;

    herbivores += lapH * 0.03;
    carnivores += lapC * 0.02;

    // Idea 1 — carnivore pursuit along the herbivore gradient
    let herbGrad = vec2<f32>(right.g - left.g, up.g - down.g);
    let fromHx = select(left.b, right.b, herbGrad.x > 0.0);
    let fromHy = select(down.b, up.b, herbGrad.y > 0.0);
    let pursuit = (fromHx - carnivores) * abs(herbGrad.x) * 0.10 * carnivores
        + (fromHy - carnivores) * abs(herbGrad.y) * 0.10 * carnivores;
    carnivores += pursuit;

    // Idea 2 — herbivore flee away from the carnivore gradient
    let carnGrad = vec2<f32>(right.b - left.b, up.b - down.b);
    let fromFx = select(right.g, left.g, carnGrad.x > 0.0);
    let fromFy = select(up.g, down.g, carnGrad.y > 0.0);
    let flee = (fromFx - herbivores) * abs(carnGrad.x) * 0.10 * herbivores
        + (fromFy - herbivores) * abs(carnGrad.y) * 0.10 * herbivores;
    herbivores += flee;

    plants = clamp(plants, 0.0, 4.0);
    herbivores = clamp(herbivores, 0.0, 4.0);
    carnivores = clamp(carnivores, 0.0, 4.0);
    toxin = clamp(toxin, 0.0, 4.0);

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.08, 0.0, mouseDist) * mouseDown;
    carnivores += mouseInfluence * 0.5;
    toxin -= mouseInfluence * 0.3;
    toxin = max(toxin, 0.0);

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.5 && rDist < 0.03) {
            let strength = smoothstep(0.03, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            plants += strength * 0.5;
        }
    }
    plants = clamp(plants, 0.0, 4.0);
    carnivores = clamp(carnivores, 0.0, 4.0);
    herbivores = clamp(herbivores, 0.0, 4.0);

    textureStore(dataTextureA, coord, vec4<f32>(plants, herbivores, carnivores, toxin));

    // HEAD fix: densities of 0.05-0.3 are the normal range, so a linear min(x,1) ramp rendered the
    // living field near-black; a saturating ramp keeps 1.0 = full colour.
    // Species pigments are mixed by fourth-power dominance (not summed), so a herd, a carnivore front and a
    // meadow keep their own hue instead of adding up to the same pale grey.
    let wP = pow(plants * 1.0, 4.0);
    let wH = pow(herbivores * 2.2, 4.0);
    let wC = pow(carnivores * 3.4, 4.0);
    let pigmentRaw = (vec3<f32>(0.15, 0.85, 0.1) * wP + vec3<f32>(0.1, 0.3, 1.0) * wH
        + vec3<f32>(1.0, 0.2, 0.05) * wC) / (wP + wH + wC + 1e-4);
    let pigment = max(mix(vec3<f32>(dot(pigmentRaw, vec3<f32>(0.333))), pigmentRaw, 1.8), vec3<f32>(0.0));
    let biomass = 1.0 - exp(-2.2 * (plants + herbivores + carnivores * 2.0));
    let toxinColor = vec3<f32>(0.4, 0.0, 0.5) * (1.0 - exp(-4.0 * toxin)) * 0.5;

    var displayColor = sourceColor.rgb * 0.06 + pigment * biomass + toxinColor;
    // ── Idea 5: kill flash — the hunting term (already computed) lights the bite sites
    displayColor += vec3<f32>(1.0, 0.55, 0.3) * clamp(hunting * 14.0, 0.0, 0.8);
    let animalEnergy = herbivores + carnivores;
    displayColor += vec3<f32>(0.1, 0.1, 0.15) * animalEnergy * 0.15;
    displayColor += vec3<f32>(0.15, 0.05, 0.02) * max(pursuit, 0.0) * 2.0;
    displayColor += vec3<f32>(0.02, 0.12, 0.18) * max(flee, 0.0) * 2.0;

    let mapped = aces(max(displayColor, vec3<f32>(0.0)));
    let ecoDensity = clamp(plants + herbivores + carnivores + toxin * 0.25, 0.0, 1.0);
    let alpha = clamp(sourceColor.a * 0.15 + ecoDensity * 0.75, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
