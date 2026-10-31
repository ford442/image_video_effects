// ═══════════════════════════════════════════════════════════════════
//  Predator-Prey Pixel Ecology
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12, 2026-10-31
//  Ideas: reciprocal hunt (prey lose energy to adjacent predators); carcass compost; pack hunting vs herd dilution (neighbour-count scaling of eat chance / predation loss); breed-ready shimmer + starvation pallor on the energy already stored; ecotone canopy rim from the neighbour census
//  A packing: raw (species, energy, age, variant)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const EMPTY: f32 = 0.0;
const PLANT: f32 = 0.2;
const HERBIVORE: f32 = 0.5;
const CARNIVORE: f32 = 0.8;

const SPECIES_EMPTY_MAX: f32 = 0.1;
const SPECIES_PLANT_MAX: f32 = 0.35;
const SPECIES_HERBIVORE_MAX: f32 = 0.65;

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

fn getSpeciesType(value: f32) -> i32 {
  if (value < SPECIES_EMPTY_MAX) { return 0; }
  if (value < SPECIES_PLANT_MAX) { return 1; }
  if (value < SPECIES_HERBIVORE_MAX) { return 2; }
  return 3;
}

fn canEat(predator: i32, prey: i32) -> bool {
  if (predator == 2 && prey == 1) { return true; }
  if (predator == 3 && prey == 2) { return true; }
  return false;
}

fn countNeighbors(coord: vec2<i32>, dims: vec2<i32>) -> vec4<i32> {
  var counts = vec4<i32>(0, 0, 0, 0);
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let neighbor = stateAt(coord + vec2<i32>(dx, dy), dims);
      let species = getSpeciesType(neighbor.r);
      counts[species] = counts[species] + 1;
    }
  }
  return counts;
}

fn findBestNeighbor(coord: vec2<i32>, dims: vec2<i32>, mySpecies: i32, forEating: bool) -> vec4<f32> {
  var bestNeighbor = vec4<f32>(0.0);
  var bestScore = -1.0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let neighbor = stateAt(coord + vec2<i32>(dx, dy), dims);
      let neighborSpecies = getSpeciesType(neighbor.r);
      if (forEating) {
        if (canEat(mySpecies, neighborSpecies)) {
          let score = neighbor.g;
          if (score > bestScore) {
            bestScore = score;
            bestNeighbor = neighbor;
          }
        }
      } else {
        if (neighborSpecies == 0) {
          let score = hash21(vec2<f32>(coord + vec2<i32>(dx, dy)));
          if (score > bestScore) {
            bestScore = score;
            bestNeighbor = vec4<f32>(f32(dx), f32(dy), 0.0, 0.0);
          }
        }
      }
    }
  }
  return bestNeighbor;
}

// HEAD fix: only counts neighbours of `kind` whose stored energy clears the Breed Threshold,
// so the shimmering "breed-ready" cells are the ones that actually found offspring.
fn readyParents(coord: vec2<i32>, dims: vec2<i32>, kind: i32, threshold: f32) -> i32 {
  var n = 0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let nb = stateAt(coord + vec2<i32>(dx, dy), dims);
      n = n + select(0, 1, getSpeciesType(nb.r) == kind && nb.g > threshold);
    }
  }
  return n;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = vec2<i32>(gid.xy);
  if (gid.x >= size.x || gid.y >= size.y) { return; }

  let dims = vec2<i32>(size);
  let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(size);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

  let eatProbability = mix(0.1, 0.5, u.zoom_params.x) * (1.0 + audio.y * 0.2);
  let deathRate = mix(0.001, 0.05, u.zoom_params.y) * (1.0 + audio.x * 0.25);
  let mutationRate = mix(0.0, 0.1, u.zoom_params.z) * (1.0 + audio.z * 0.3);
  let breedThreshold = mix(0.5, 0.9, u.zoom_params.w);

  let state = stateAt(coord, dims);
  var species = state.r;
  var energy = state.g;
  var age = state.b;
  var variant = state.a;
  var myType = getSpeciesType(species);

  let rand = hash21(uv * 1000.0 + vec2<f32>(time * 100.0));
  // HEAD fix: uv*2000 is exactly 2x the uv*1000 behind `rand`, so rand2 was locked to rand and the
  // spawn lottery (rand tiny -> rand2 < 0.7) only ever produced plants. Decorrelated lattice below.
  let rand2 = hash21(vec2<f32>(coord) * 0.7313 + vec2<f32>(time * 37.0 + 11.0, time * 19.0 + 3.0));

  // HEAD fix: death shares no hash with the spawn / birth lotteries. At HEAD births fired on
  // `rand < ~0.01-0.06` and death on `rand < deathRate` (0.0165 at default), so a newborn died
  // in its own birth frame (animals composted to plants, plants to empty) and nothing ever lived.
  let rand3 = hash21(vec2<f32>(coord.yx) * 0.4177 + vec2<f32>(time * 23.0 + 5.0, time * 53.0 + 7.0));

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  if (myType == 0 && rand < 0.01 + sourceLum * 0.05) {
    if (rand2 < 0.7) {
      species = PLANT;
      energy = 0.5;
    } else if (rand2 < 0.9) {
      species = HERBIVORE;
      energy = 0.6;
    } else {
      species = CARNIVORE;
      energy = 0.7;
    }
    age = 0.0;
    variant = rand;
    myType = getSpeciesType(species);
  }

  let mouse = u.zoom_config.yz;
  let mouseDist = length(uv - mouse);
  if (mouseDist < 0.03 && myType == 0) {
    species = CARNIVORE;
    energy = 1.0;
    age = 0.0;
    myType = 3;
  }

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rippleAge = time - ripple.z;
    if (rippleAge > 0.0 && rippleAge < 0.5) {
      let dist = length(uv - ripple.xy);
      if (dist < 0.02 && myType == 0) {
        species = PLANT;
        energy = 1.0;
        age = 0.0;
        myType = 1;
      }
    }
  }

  let neighbors = countNeighbors(coord, dims);

  if (myType > 0) {
    age = age + 0.001;

    if (myType == 1) {
      energy = energy + sourceLum * 0.01;
      energy = min(energy, 1.0);
      // Idea 1 — reciprocal hunt: plants lose energy to adjacent herbivores
      energy = energy - f32(neighbors[2]) * eatProbability * 0.018;
    }

    if (myType >= 2) {
      let preyNeighbor = findBestNeighbor(coord, dims, myType, true);
      let preyType = getSpeciesType(preyNeighbor.r);
      // ── Idea 3: pack hunting — each adjacent carnivore improves a carnivore's strike chance
      let packBoost = select(1.0, 1.0 + 0.15 * f32(neighbors[3]), myType == 3);
      if (canEat(myType, preyType) && rand < eatProbability * packBoost) {
        energy = energy + preyNeighbor.g * 0.5;
        energy = min(energy, 1.0);
      }
      energy = energy - 0.005;
      if (myType == 3) {
        energy = energy - 0.003;
      }
      // Idea 1 — herbivores lose energy to adjacent carnivores
      // ── Idea 3: herd dilution — the same census shares each predator's bite among herd-mates
      if (myType == 2) {
        let dilution = 1.0 / (1.0 + 0.08 * f32(neighbors[2]));
        energy = energy - f32(neighbors[3]) * eatProbability * 0.022 * dilution;
      }
    }

    if (energy <= 0.0 || age > 1.0 || rand3 < deathRate) {
      // Idea 2 — carcass compost: animals become plants instead of empty
      if (myType >= 2) {
        species = PLANT;
        energy = 0.22 + variant * 0.08;
        age = 0.0;
        myType = 1;
      } else {
        species = EMPTY;
        energy = 0.0;
        age = 0.0;
        myType = 0;
      }
    }

    if (myType > 0 && energy > breedThreshold && rand2 < 0.12) {
      // HEAD fix: breeding cost also applies when the only free sites are prey cells
      let sites = neighbors[0] + select(0, neighbors[myType - 1], myType >= 2);
      if (sites > 0) {
        energy = energy * 0.5;
      }
    }

    if (rand < mutationRate && myType > 0) {
      variant = fract(variant + 0.1);
    }
  }

  if (myType == 0) {
    if (neighbors[1] >= 2 && rand < 0.02) {
      species = PLANT;
      energy = 0.3;
      age = 0.0;
      myType = 1;
    }
    if (neighbors[2] >= 2 && rand < 0.01) {
      species = HERBIVORE;
      energy = 0.4;
      age = 0.0;
      myType = 2;
    }
    if (neighbors[3] >= 2 && rand < 0.005) {
      species = CARNIVORE;
      energy = 0.5;
      age = 0.0;
      myType = 3;
    }
  }

  // HEAD fix: at HEAD offspring could only be born into EMPTY cells, but plants (and composted
  // carcasses) fill every cell within seconds, so animals went extinct and the field became a
  // green carpet. Fed parents now settle on their prey's cell (a grazed plant / a taken herbivore).
  // Settlement is rate-limited (1% / 0.3% per ready parent) and the parent's halving cost fires at 12%/frame,
  // so a parent pays roughly what it sows and the pyramid stays plants > herbivores > carnivores.
  if (myType == 1) {
    if (rand2 < 0.01 * f32(readyParents(coord, dims, 2, breedThreshold))) {
      species = HERBIVORE;
      energy = 0.45;
      age = 0.0;
      myType = 2;
    }
  } else if (myType == 2) {
    if (rand2 < 0.003 * f32(readyParents(coord, dims, 3, breedThreshold))) {
      species = CARNIVORE;
      energy = 0.55;
      age = 0.0;
      myType = 3;
    }
  }

  textureStore(dataTextureA, coord, vec4<f32>(species, energy, age, variant));

  var finalColor = sourceColor.rgb * 0.3;
  let speciesType = getSpeciesType(species);
  if (speciesType == 1) {
    let plantColor = vec3<f32>(0.2, 0.6 + energy * 0.4, 0.2);
    finalColor = mix(finalColor, plantColor, 0.8);
  } else if (speciesType == 2) {
    let herbColor = vec3<f32>(0.2, 0.4 + energy * 0.3, 0.8);
    finalColor = mix(finalColor, herbColor, 0.8);
  } else if (speciesType == 3) {
    let carnColor = vec3<f32>(0.8, 0.2 + energy * 0.3, 0.2);
    finalColor = mix(finalColor, carnColor, 0.8);
  }

  if (speciesType > 0) {
    finalColor = finalColor + vec3<f32>(energy * 0.3);
    // ── Idea 4: starvation pallor — low-energy cells bleach toward grey (reads the stored energy)
    let hunger = clamp(1.0 - energy / 0.2, 0.0, 1.0);
    let greyLum = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    finalColor = mix(finalColor, vec3<f32>(greyLum), hunger * 0.45);
    // ── Idea 4: breed-ready shimmer — cells above the Breed Threshold pulse warm
    let ready = select(0.0, 1.0, energy > breedThreshold && speciesType >= 2);
    finalColor = finalColor + vec3<f32>(0.22, 0.16, 0.05) * ready * (0.5 + 0.5 * sin(time * 6.0 + variant * 20.0));
    // ── Idea 5: ecotone canopy rim — interior cells shade down, colony margins keep full light
    let same = f32(neighbors[speciesType]) / 8.0;
    finalColor = finalColor * (0.8 + 0.2 * (1.0 - same)) + finalColor * 0.18 * (1.0 - same) * (1.0 - same);
  }
  if (speciesType > 0 && variant > 0.0) {
    let hueShift = variant * 0.2;
    finalColor = finalColor * vec3<f32>(1.0 + hueShift, 1.0, 1.0 - hueShift);
  }

  let mapped = aces(max(finalColor, vec3<f32>(0.0)));
  let alpha = clamp(sourceColor.a * 0.2 + select(0.12, 0.55 + energy * 0.4, speciesType > 0), 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
