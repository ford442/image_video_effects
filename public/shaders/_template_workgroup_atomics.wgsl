// ═══════════════════════════════════════════════════════════════════════════════
//  Workgroup-Level Atomic Reduction Template
//  
//  Use this pattern when you need atomic operations in particle/fluid shaders.
//  Instead of global atomics per thread, accumulate to workgroup memory then
//  do a single global atomic per workgroup. 10-100x faster on most GPUs.
// ═══════════════════════════════════════════════════════════════════════════════

// Example: Particle density histogram for fluid simulation

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read_write> globalHistogram: array<atomic<u32>>;
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

struct Particle {
    position: vec2<f32>,
    velocity: vec2<f32>,
    mass: f32,
};

// ═══════════════════════════════════════════════════════════════════════════════
// WORKGROUP SHARED MEMORY
// ═══════════════════════════════════════════════════════════════════════════════

const WORKGROUP_SIZE: u32 = 256u;

// Local histogram in workgroup memory (much faster than global atomics!)
var<workgroup> localHistogram: array<atomic<u32>, 256>;

// For large grids, use multiple bins per thread
// const BINS_PER_THREAD: u32 = 4u;
// var<workgroup> localHistogram: array<atomic<u32>, 1024>;

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

// Convert position to grid cell (bin)
fn positionToCell(pos: vec2<f32>, resolution: vec2<f32>) -> u32 {
    let normalized = clamp(pos, vec2(0.0), vec2(1.0));
    let cell = vec2<u32>(normalized * 16.0);  // 16x16 grid
    return cell.y * 16u + cell.x;
}

// Reset local histogram (cooperative)
fn clearLocalHistogram(lid: vec3<u32>) {
    // Each thread clears multiple bins (if histogram is larger than workgroup)
    for (var i = lid.x; i < 256u; i = i + WORKGROUP_SIZE) {
        atomicStore(&localHistogram[i], 0u);
    }
    workgroupBarrier();
}

// Accumulate to local histogram (FAST - workgroup memory)
fn accumulateLocal(cellIndex: u32) {
    if (cellIndex < 256u) {
        atomicAdd(&localHistogram[cellIndex], 1u);
    }
}

// Flush local histogram to global (single atomic per bin per workgroup)
fn flushToGlobal(lid: vec3<u32>) {
    workgroupBarrier();
    
    // Each thread flushes multiple bins
    for (var i = lid.x; i < 256u; i = i + WORKGROUP_SIZE) {
        let localCount = atomicLoad(&localHistogram[i]);
        if (localCount > 0u) {
            // Single global atomic per workgroup per bin!
            atomicAdd(&globalHistogram[i], localCount);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REDUCTION FOR FLOATING-POINT VALUES (e.g., density, velocity)
// ═══════════════════════════════════════════════════════════════════════════════

// For floating-point reductions, use prefix-sum pattern
var<workgroup> localFloatBuffer: array<f32, WORKGROUP_SIZE>;

fn workgroupSum(value: f32, lid: vec3<u32>) -> f32 {
    // Store in local memory
    localFloatBuffer[lid.x] = value;
    workgroupBarrier();
    
    // Parallel reduction tree
    // Round 1: stride = 128
    if (lid.x < 128u) {
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 128u];
    }
    workgroupBarrier();
    
    // Round 2: stride = 64
    if (lid.x < 64u) {
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 64u];
    }
    workgroupBarrier();
    
    // Round 3-7: continue halving (can use loop but unrolled is faster)
    if (lid.x < 32u) {
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 32u];
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 16u];
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 8u];
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 4u];
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 2u];
        localFloatBuffer[lid.x] += localFloatBuffer[lid.x + 1u];
    }
    workgroupBarrier();
    
    // Result is in localFloatBuffer[0]
    return localFloatBuffer[0];
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 1: PARTICLE HISTOGRAM (GRID DENSITY)
// ═══════════════════════════════════════════════════════════════════════════════

@compute @workgroup_size(256, 1, 1)
fn computeParticleHistogram(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(workgroup_id) wid: vec3<u32>,
) {
    // Step 1: Clear local histogram
    clearLocalHistogram(lid);
    
    // Step 2: Each thread processes multiple particles (stride pattern)
    let globalOffset = wid.x * WORKGROUP_SIZE;
    
    for (var i = gid.x; i < uniforms.particleCount; i = i + (WORKGROUP_SIZE * 65535u)) {
        let particle = particles[i];
        let cellIndex = positionToCell(particle.position, uniforms.gridResolution);
        accumulateLocal(cellIndex);
    }
    
    // Step 3: Flush to global (single atomic per bin per workgroup!)
    flushToGlobal(lid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 2: VELOCITY FIELD ACCUMULATION (Particle-In-Cell)
// ═══════════════════════════════════════════════════════════════════════════════

// Store velocity accumulations locally
var<workgroup> localVelX: array<atomic<i32>, 256>;
var<workgroup> localVelY: array<atomic<i32>, 256>;
var<workgroup> localMass: array<atomic<u32>, 256>;

fn accumulateVelocity(cellIndex: u32, velocity: vec2<f32>, mass: f32) {
    if (cellIndex < 256u) {
        // Quantize float to int for atomic operations
        // Scale by 1000 to preserve some precision
        let vx = i32(velocity.x * 1000.0);
        let vy = i32(velocity.y * 1000.0);
        let m = u32(mass * 1000.0);
        
        atomicAdd(&localVelX[cellIndex], vx);
        atomicAdd(&localVelY[cellIndex], vy);
        atomicAdd(&localMass[cellIndex], m);
    }
}

fn flushVelocityToGlobal(lid: vec3<u32>) {
    workgroupBarrier();
    
    for (var i = lid.x; i < 256u; i = i + WORKGROUP_SIZE) {
        let vx = atomicLoad(&localVelX[i]);
        let vy = atomicLoad(&localVelY[i]);
        let m = atomicLoad(&localMass[i]);
        
        if (m > 0u) {
            // Convert back to float and accumulate globally
            // (You'd need separate global buffers for this)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 3: PREFIX SUM (for sort, scan operations)
// ═══════════════════════════════════════════════════════════════════════════════

var<workgroup> localPrefixSum: array<u32, WORKGROUP_SIZE>;

fn workgroupPrefixSum(value: u32, lid: vec3<u32>) -> u32 {
    // Store value
    localPrefixSum[lid.x] = value;
    workgroupBarrier();
    
    // Up-sweep (reduction)
    var offset = 1u;
    for (var d = WORKGROUP_SIZE >> 1u; d > 0u; d = d >> 1u) {
        if (lid.x < d) {
            let ai = offset * (2u * lid.x + 1u) - 1u;
            let bi = offset * (2u * lid.x + 2u) - 1u;
            localPrefixSum[bi] += localPrefixSum[ai];
        }
        offset = offset << 1u;
        workgroupBarrier();
    }
    
    // Clear last element for exclusive scan
    if (lid.x == 0u) {
        localPrefixSum[WORKGROUP_SIZE - 1u] = 0u;
    }
    workgroupBarrier();
    
    // Down-sweep
    for (var d = 1u; d < WORKGROUP_SIZE; d = d << 1u) {
        offset = offset >> 1u;
        if (lid.x < d) {
            let ai = offset * (2u * lid.x + 1u) - 1u;
            let bi = offset * (2u * lid.x + 2u) - 1u;
            let t = localPrefixSum[ai];
            localPrefixSum[ai] = localPrefixSum[bi];
            localPrefixSum[bi] += t;
        }
        workgroupBarrier();
    }
    
    // Return prefix sum up to this thread
    return localPrefixSum[lid.x];
}

// ═══════════════════════════════════════════════════════════════════════════════
// PERFORMANCE NOTES
// ═══════════════════════════════════════════════════════════════════════════════
//
// Global Atomic (per thread):     ~100-1000ns per operation
// Workgroup Atomic (per thread):  ~1-10ns per operation  
// Reduction tree (per workgroup): ~log2(n) operations
//
// For 256 threads:
// - 256 global atomics:           25,600-256,000ns
// - 256 workgroup atomics:        256-2,560ns
// - 1 workgroup reduce + 1 global: ~100ns + 1 global atomic
//
// Speedup: 10-1000x depending on contention
//
// ═══════════════════════════════════════════════════════════════════════════════
