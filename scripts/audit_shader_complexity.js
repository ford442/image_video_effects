#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════
//  Shader Complexity Audit
//  Scans all WGSL files and identifies candidates for upgrade based on:
//    - Line count (small = candidate)
//    - Feature richness (few features = candidate)
//    - Algorithmic sophistication (missing fbm/sdf/raymarch/noise = candidate)
//  Outputs: audit-results.json with prioritized upgrade candidates
// ═══════════════════════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');

const SHADERS_DIR = path.join(__dirname, '..', 'public', 'shaders');
const DEFINITIONS_DIR = path.join(__dirname, '..', 'shader_definitions');
const PHASE_B_TARGETS = path.join(__dirname, '..', 'swarm-tasks', 'phase-b', 'phase-b-upgrade-targets.json');
const OUTPUT_PATH = path.join(__dirname, '..', 'swarm-outputs', 'audit-results.json');

// Feature detection patterns
const PATTERNS = {
  hasFbm: /fbm\s*\(/i,
  hasSdf: /sd(Circle|Box|Line|Capsule|Grid|Grid3D|Sphere|Cube|Cylinder|Plane)/i,
  hasRaymarch: /raymarch|march|ro|rd/i,
  hasNoise: /(valueNoise|simplexNoise|perlinNoise|worley|gabor|hash21|hash11|hash22|noise)/i,
  hasCurl: /curlNoise|curl2D|curl3D/i,
  hasReactionDiffusion: /reaction.diffusion|gray.scott|turing/i,
  hasFluid: /navier.stokes|jacobi|divergence|pressure|advect/i,
  hasTemporal: /temporal|feedback|accumulat|ping.pong|history|trail|echo/i,
  hasDepthAware: /readDepthTexture|depth|calculateCoC/i,
  hasAudioReactive: /plasmaBuffer|audio|bass|mids|treble|beat|fft/i,
  hasMouseDriven: /zoom_config\.yz|mouse|ripples/i,
  hasMultiPass: /dataTextureA|dataTextureB|pass1|pass2/i,
  hasHdr: /HDR|ACES|tone.map|reinhard|agx/i,
  hasVoronoi: /voronoi/i,
  hasDomainWarp: /domain.warp|warp/i,
};

function findShaderJson(shaderId) {
  const cats = fs.readdirSync(DEFINITIONS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);
  for (const cat of cats) {
    const p = path.join(DEFINITIONS_DIR, cat, `${shaderId}.json`);
    if (fs.existsSync(p)) return JSON.parse(fs.readFileSync(p, 'utf8'));
  }
  return null;
}

function loadPhaseBTargets() {
  if (!fs.existsSync(PHASE_B_TARGETS)) return {};
  const data = JSON.parse(fs.readFileSync(PHASE_B_TARGETS, 'utf8'));
  const map = {};
  for (const cat of Object.values(data.categories || {})) {
    for (const item of cat) {
      map[item.id] = { ...item, categoryTrack: cat };
    }
  }
  return map;
}

function analyzeShader(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');
  const lineCount = lines.length;
  const id = path.basename(filePath, '.wgsl');

  const features = {};
  for (const [key, regex] of Object.entries(PATTERNS)) {
    features[key] = regex.test(content);
  }

  // Count algorithmic richness score (0–15)
  const algoScore = Object.values(features).filter(Boolean).length;

  // Detect feature flags from JSON definition
  const json = findShaderJson(id);
  const jsonFeatures = json?.features || [];
  const category = json?.category || 'unknown';

  // Heuristic: small AND low algorithmic score = upgrade candidate
  const isCandidate = lineCount < 100 || algoScore < 5;

  return {
    id,
    lineCount,
    algoScore,
    features,
    jsonFeatures,
    category,
    isCandidate,
    hasJson: json !== null,
  };
}

function main() {
  const files = fs.readdirSync(SHADERS_DIR)
    .filter(f => f.endsWith('.wgsl'))
    .map(f => path.join(SHADERS_DIR, f));

  const phaseBMap = loadPhaseBTargets();
  const results = [];

  for (const file of files) {
    const analysis = analyzeShader(file);
    const phaseB = phaseBMap[analysis.id];

    if (analysis.isCandidate || phaseB) {
      results.push({
        ...analysis,
        phaseBTarget: phaseB || null,
      });
    }
  }

  // Sort: small line count first, then low algo score
  results.sort((a, b) => {
    if (a.lineCount !== b.lineCount) return a.lineCount - b.lineCount;
    return a.algoScore - b.algoScore;
  });

  // Categorize
  const smallShaders = results.filter(r => r.lineCount < 100);
  const mediumShaders = results.filter(r => r.lineCount >= 100 && r.lineCount < 140 && r.algoScore < 5);
  const phaseBPending = results.filter(r => r.phaseBTarget && r.phaseBTarget.status !== 'completed');

  const output = {
    generated: new Date().toISOString(),
    totalWgslFiles: files.length,
    totalCandidates: results.length,
    smallShaders: {
      count: smallShaders.length,
      shaders: smallShaders.map(r => ({
        id: r.id,
        lines: r.lineCount,
        algoScore: r.algoScore,
        category: r.category,
        features: r.jsonFeatures,
        phaseBTrack: r.phaseBTarget ? r.phaseBTarget.rationale : null,
      })),
    },
    mediumShaders: {
      count: mediumShaders.length,
      shaders: mediumShaders.map(r => ({
        id: r.id,
        lines: r.lineCount,
        algoScore: r.algoScore,
        category: r.category,
        features: r.jsonFeatures,
      })),
    },
    phaseBPending: {
      count: phaseBPending.length,
      shaders: phaseBPending.map(r => ({
        id: r.id,
        lines: r.lineCount,
        algoScore: r.algoScore,
        track: r.phaseBTarget.rationale,
        priority: r.phaseBTarget.priority,
      })),
    },
  };

  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(output, null, 2));
  console.log(`✅ Audit complete. ${results.length} candidates found.`);
  console.log(`   Small (<100 lines): ${smallShaders.length}`);
  console.log(`   Medium (100-140 lines, low algo): ${mediumShaders.length}`);
  console.log(`   Phase B pending: ${phaseBPending.length}`);
  console.log(`   Output: ${OUTPUT_PATH}`);
}

main();
