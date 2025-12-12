// Predator-Prey Pixel Ecology
// Cellular automata ecosystem simulation with eating, breeding, and death

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // species & energy
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // temp buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous ecosystem state
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=EatProbability, y=DeathRate, z=MutationRate, w=BreedThreshold
  ripples: array<vec4<f32>, 50>,
};

// Species types encoded in R channel:
// 0.0 = Empty
// 0.1-0.3 = Plants (prey level 0)
// 0.4-0.6 = Herbivores (prey level 1, predator of plants)
// 0.7-0.9 = Carnivores (predator of herbivores)
// 1.0 = Super predator

const EMPTY: f32 = 0.0;
const PLANT: f32 = 0.2;
const HERBIVORE: f32 = 0.5;
const CARNIVORE: f32 = 0.8;

// G channel = Energy (0.0 - 1.0)
// B channel = Age (0.0 - 1.0)
// A channel = Mutation variant

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

// Species classification thresholds for ecosystem balance
const SPECIES_EMPTY_MAX: f32 = 0.1;      // 0.0 - 0.1 = Empty
const SPECIES_PLANT_MAX: f32 = 0.35;     // 0.1 - 0.35 = Plant
const SPECIES_HERBIVORE_MAX: f32 = 0.65; // 0.35 - 0.65 = Herbivore
                                          // 0.65+ = Carnivore

// Get species type from encoded value
fn getSpeciesType(value: f32) -> i32 {
  if (value < SPECIES_EMPTY_MAX) { return 0; } // Empty
  if (value < SPECIES_PLANT_MAX) { return 1; } // Plant
  if (value < SPECIES_HERBIVORE_MAX) { return 2; } // Herbivore
  return 3; // Carnivore
}

// Check if predator can eat prey
fn canEat(predator: i32, prey: i32) -> bool {
  if (predator == 2 && prey == 1) { return true; } // Herbivore eats Plant
  if (predator == 3 && prey == 2) { return true; } // Carnivore eats Herbivore
  return false;
}

// Count neighbors of each type
fn countNeighbors(uv: vec2<f32>, texelSize: vec2<f32>) -> vec4<i32> {
  var counts = vec4<i32>(0, 0, 0, 0); // empty, plant, herbivore, carnivore
  
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      
      let neighborUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
      let neighbor = textureSampleLevel(dataTextureC, non_filtering_sampler, neighborUV, 0.0);
      let species = getSpeciesType(neighbor.r);
      
      counts[species] = counts[species] + 1;
    }
  }
  
  return counts;
}

// Find best neighbor for predation or breeding
fn findBestNeighbor(uv: vec2<f32>, texelSize: vec2<f32>, mySpecies: i32, forEating: bool) -> vec4<f32> {
  var bestNeighbor = vec4<f32>(0.0);
  var bestScore = -1.0;
  
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      
      let neighborUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
      let neighbor = textureSampleLevel(dataTextureC, non_filtering_sampler, neighborUV, 0.0);
      let neighborSpecies = getSpeciesType(neighbor.r);
      
      if (forEating) {
        if (canEat(mySpecies, neighborSpecies)) {
          let score = neighbor.g; // Prefer high energy prey
          if (score > bestScore) {
            bestScore = score;
            bestNeighbor = neighbor;
          }
        }
      } else {
        // For breeding - find empty space
        if (neighborSpecies == 0) {
          let score = hash21(neighborUV * 1000.0);
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let frame = u.config.y;
  
  // Parameters
  let eatProbability = mix(0.1, 0.5, u.zoom_params.x);
  let deathRate = mix(0.001, 0.05, u.zoom_params.y);
  let mutationRate = mix(0.0, 0.1, u.zoom_params.z);
  let breedThreshold = mix(0.5, 0.9, u.zoom_params.w);
  
  // Read current state
  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var species = state.r;
  var energy = state.g;
  var age = state.b;
  var variant = state.a;
  
  let myType = getSpeciesType(species);
  
  // Random for this frame/pixel
  let rand = hash21(uv * 1000.0 + vec2<f32>(time * 100.0));
  let rand2 = hash21(uv * 2000.0 + vec2<f32>(time * 50.0 + 1.0));
  
  // Source image influence
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Initialize from source image if first frame or empty
  if (myType == 0 && rand < 0.01 + sourceLum * 0.05) {
    // Spawn new life based on luminance
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
  }
  
  // Mouse spawns predators
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDist = length(uv - mouse);
  if (mouseDist < 0.03 && myType == 0) {
    species = CARNIVORE;
    energy = 1.0;
    age = 0.0;
  }
  
  // Ripples spawn plants (food sources)
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 0.5) {
        let dist = length(uv - ripple.xy);
        if (dist < 0.02 && myType == 0) {
          species = PLANT;
          energy = 1.0;
          age = 0.0;
        }
      }
    }
  }
  
  // Living entity logic
  if (myType > 0) {
    // Age
    age = age + 0.001;
    
    // Plants photosynthesize
    if (myType == 1) {
      energy = energy + sourceLum * 0.01;
      energy = min(energy, 1.0);
      
      // Plants spread
      if (energy > breedThreshold && rand < 0.02) {
        // Will spawn in empty neighbor (handled by empty cells checking)
      }
    }
    
    // Animals try to eat
    if (myType >= 2) {
      let preyNeighbor = findBestNeighbor(uv, texelSize, myType, true);
      let preyType = getSpeciesType(preyNeighbor.r);
      
      if (canEat(myType, preyType) && rand < eatProbability) {
        // Eat! Gain energy
        energy = energy + preyNeighbor.g * 0.5;
        energy = min(energy, 1.0);
      }
      
      // Lose energy over time
      energy = energy - 0.005;
      
      // Carnivores lose energy faster
      if (myType == 3) {
        energy = energy - 0.003;
      }
    }
    
    // Death conditions
    if (energy <= 0.0 || age > 1.0 || rand < deathRate) {
      species = EMPTY;
      energy = 0.0;
      age = 0.0;
    }
    
    // Breeding
    if (energy > breedThreshold && rand2 < 0.05) {
      // Check for empty neighbor
      let neighbors = countNeighbors(uv, texelSize);
      if (neighbors[0] > 0) {
        energy = energy * 0.5; // Split energy with offspring
      }
    }
    
    // Mutation
    if (rand < mutationRate && myType > 0) {
      variant = fract(variant + 0.1);
    }
  }
  
  // Empty cells can be colonized
  if (myType == 0) {
    let neighbors = countNeighbors(uv, texelSize);
    
    // Plants spread if neighbors exist
    if (neighbors[1] >= 2 && rand < 0.02) {
      species = PLANT;
      energy = 0.3;
      age = 0.0;
    }
    
    // Animals breed into empty space
    if (neighbors[2] >= 2 && rand < 0.01) {
      species = HERBIVORE;
      energy = 0.4;
      age = 0.0;
    }
    
    if (neighbors[3] >= 2 && rand < 0.005) {
      species = CARNIVORE;
      energy = 0.5;
      age = 0.0;
    }
  }
  
  // Store updated state
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(species, energy, age, variant));
  
  // Visualization
  var finalColor = sourceColor.rgb * 0.3; // Dim background
  
  let speciesType = getSpeciesType(species);
  
  if (speciesType == 1) {
    // Plants - green
    let plantColor = vec3<f32>(0.2, 0.6 + energy * 0.4, 0.2);
    finalColor = mix(finalColor, plantColor, 0.8);
  } else if (speciesType == 2) {
    // Herbivores - blue
    let herbColor = vec3<f32>(0.2, 0.4 + energy * 0.3, 0.8);
    finalColor = mix(finalColor, herbColor, 0.8);
  } else if (speciesType == 3) {
    // Carnivores - red
    let carnColor = vec3<f32>(0.8, 0.2 + energy * 0.3, 0.2);
    finalColor = mix(finalColor, carnColor, 0.8);
  }
  
  // Add energy glow
  if (speciesType > 0) {
    let glow = energy * 0.3;
    finalColor = finalColor + vec3<f32>(glow);
  }
  
  // Variant hue shift
  if (speciesType > 0 && variant > 0.0) {
    let hueShift = variant * 0.2;
    finalColor = finalColor * vec3<f32>(1.0 + hueShift, 1.0, 1.0 - hueShift);
  }
  
  // Clamp
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
