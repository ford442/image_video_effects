// ═══════════════════════════════════════════════════════════════════
//  Predator-Prey Pixel Ecology
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12
//  Ideas: reciprocal hunt (prey lose energy to adjacent predators); carcass compost
//  A packing: raw (species, energy, age, variant)
// ═══════════════════════════════════════════════════════════════════

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
  let rand2 = hash21(uv * 2000.0 + vec2<f32>(time * 50.0 + 1.0));

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
      if (canEat(myType, preyType) && rand < eatProbability) {
        energy = energy + preyNeighbor.g * 0.5;
        energy = min(energy, 1.0);
      }
      energy = energy - 0.005;
      if (myType == 3) {
        energy = energy - 0.003;
      }
      // Idea 1 — herbivores lose energy to adjacent carnivores
      if (myType == 2) {
        energy = energy - f32(neighbors[3]) * eatProbability * 0.022;
      }
    }

    if (energy <= 0.0 || age > 1.0 || rand < deathRate) {
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

    if (myType > 0 && energy > breedThreshold && rand2 < 0.05) {
      if (neighbors[0] > 0) {
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
