#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════
//  Shader Upgrade Swarm Orchestrator
//  Usage:
//    node scripts/run-upgrade-swarm.js --prepare          # Generate prompts only
//    node scripts/run-upgrade-swarm.js --dispatch         # Run with AI API
//    node scripts/run-upgrade-swarm.js --agent-dispatch   # Print Agent-tool manifest
//    node scripts/run-upgrade-swarm.js --batch=4          # Limit parallel batch size
// ═══════════════════════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const QUEUE_PATH = path.join(PROJECT_ROOT, 'swarm-tasks', 'upgrade-queue.json');
const PROMPTS_DIR = path.join(PROJECT_ROOT, 'swarm-tasks', 'prompts');
const TEMPLATES_DIR = path.join(PROJECT_ROOT, 'agents', 'prompt-templates');
const PROGRESS_PATH = path.join(PROJECT_ROOT, 'swarm-outputs', 'upgrade-progress.json');
const SHADERS_DIR = path.join(PROJECT_ROOT, 'public', 'shaders');
const DEFINITIONS_DIR = path.join(PROJECT_ROOT, 'shader_definitions');

const BINDING_HEADER = `// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};`;

function parseArgs() {
  const args = process.argv.slice(2);
  return {
    prepare: args.includes('--prepare'),
    dispatch: args.includes('--dispatch'),
    agentDispatch: args.includes('--agent-dispatch'),
    batch: parseInt(args.find(a => a.startsWith('--batch='))?.split('=')[1] || '4', 10),
    help: args.includes('--help') || args.includes('-h'),
  };
}

function printHelp() {
  console.log(`
Shader Upgrade Swarm Orchestrator

Usage:
  node scripts/run-upgrade-swarm.js [options]

Options:
  --prepare           Generate agent prompt files for pending shaders (default)
  --dispatch          Spawn parallel subagents via external AI API (needs API key)
  --agent-dispatch    Output JSON manifest for AI CLI Agent-tool dispatch
  --batch=N           Process N shaders in parallel (default: 4)
  --help, -h          Show this help

Files:
  Queue:     swarm-tasks/upgrade-queue.json
  Prompts:   swarm-tasks/prompts/<shader-id>.md
  Progress:  swarm-outputs/upgrade-progress.json
`);
}

function loadQueue() {
  if (!fs.existsSync(QUEUE_PATH)) {
    console.error('❌ Queue file not found:', QUEUE_PATH);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(QUEUE_PATH, 'utf8'));
}

function loadProgress() {
  if (fs.existsSync(PROGRESS_PATH)) {
    return JSON.parse(fs.readFileSync(PROGRESS_PATH, 'utf8'));
  }
  return { runs: [], current: {} };
}

function saveProgress(progress) {
  fs.writeFileSync(PROGRESS_PATH, JSON.stringify(progress, null, 2));
}

function findShaderJson(shaderId) {
  const categories = fs.readdirSync(DEFINITIONS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);
  for (const cat of categories) {
    const jsonPath = path.join(DEFINITIONS_DIR, cat, `${shaderId}.json`);
    if (fs.existsSync(jsonPath)) return jsonPath;
  }
  return null;
}

function findShaderWgsl(shaderId) {
  const wgslPath = path.join(SHADERS_DIR, `${shaderId}.wgsl`);
  return fs.existsSync(wgslPath) ? wgslPath : null;
}

function getTemplate(role) {
  const templatePath = path.join(TEMPLATES_DIR, `${role.toLowerCase()}.md`);
  if (fs.existsSync(templatePath)) {
    return fs.readFileSync(templatePath, 'utf8');
  }
  console.warn(`⚠️  Template not found for role "${role}", using Optimizer fallback.`);
  return fs.readFileSync(path.join(TEMPLATES_DIR, 'optimizer.md'), 'utf8');
}

function generatePrompt(item) {
  const wgslPath = findShaderWgsl(item.id);
  const jsonPath = findShaderJson(item.id);

  if (!wgslPath) {
    throw new Error(`WGSL file not found for shader: ${item.id}`);
  }

  const wgslContent = fs.readFileSync(wgslPath, 'utf8');
  const jsonContent = jsonPath ? fs.readFileSync(jsonPath, 'utf8') : '{ /* no JSON found */ }';
  const template = getTemplate(item.agent_role);

  const prompt = `# Shader Upgrade Task: \`${item.id}\`

## Metadata
- **Shader ID**: ${item.id}
- **Agent Role**: ${item.agent_role}
- **Current Size**: ${item.size} bytes
- **Target Line Count**: ~${item.target_lines} lines
- **Status**: ${item.status}

## Immutable Rules
The following MUST NOT be changed:
1. The 13-binding contract header (copy exactly).
2. The \`Uniforms\` struct definition.
3. \`@workgroup_size\` unless the shader already uses shared memory or explicit local_invocation_id math.
4. Do NOT install new npm packages.
5. Do NOT modify Renderer.ts, types.ts, or bind groups.

${BINDING_HEADER}

---

## Current WGSL Source
\`\`\`wgsl
${wgslContent}
\`\`\`

## Current JSON Definition
\`\`\`json
${jsonContent}
\`\`\`

---

## Agent Specialization
${template}

---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly ${item.target_lines} lines (±20%).
5. Write a brief upgrade rationale (2-3 sentences).

## Output Format
Return exactly two code blocks:
1. \`\`\`wgsl\n[upgraded shader source]\n\`\`\`
2. \`\`\`json\n[updated shader definition]\n\`\`\`

If the JSON does not need changes, return the original JSON unchanged.
`;

  return prompt;
}

function writePrompt(item) {
  const prompt = generatePrompt(item);
  const outPath = path.join(PROMPTS_DIR, `${item.id}.md`);
  fs.mkdirSync(PROMPTS_DIR, { recursive: true });
  fs.writeFileSync(outPath, prompt);
  return outPath;
}

function validateShader(shaderId) {
  const errors = [];
  const wgslPath = findShaderWgsl(shaderId);
  if (!wgslPath) {
    errors.push('WGSL file missing');
    return errors;
  }

  const wgsl = fs.readFileSync(wgslPath, 'utf8');

  // Check 13-binding contract presence
  const requiredBindings = [
    '@group(0) @binding(0) var u_sampler',
    '@group(0) @binding(1) var readTexture',
    '@group(0) @binding(2) var writeTexture',
    '@group(0) @binding(3) var<uniform> u: Uniforms',
    '@group(0) @binding(4) var readDepthTexture',
    '@group(0) @binding(5) var non_filtering_sampler',
    '@group(0) @binding(6) var writeDepthTexture',
    '@group(0) @binding(7) var dataTextureA',
    '@group(0) @binding(8) var dataTextureB',
    '@group(0) @binding(9) var dataTextureC',
    '@group(0) @binding(10) var<storage, read_write> extraBuffer',
    '@group(0) @binding(11) var comparison_sampler',
    '@group(0) @binding(12) var<storage, read> plasmaBuffer',
  ];
  for (const binding of requiredBindings) {
    if (!wgsl.includes(binding)) {
      errors.push(`Missing binding: ${binding}`);
    }
  }

  // Check compute stage
  if (!wgsl.includes('@compute')) {
    errors.push('Missing @compute attribute');
  }

  // Check main entry point
  if (!wgsl.includes('fn main(')) {
    errors.push('Missing fn main entry point');
  }

  // Naga validation if available
  try {
    execSync(`naga "${wgslPath}"`, { stdio: 'pipe' });
  } catch (e) {
    const stderr = e.stderr?.toString() || e.message || '';
    if (stderr.includes('error:')) {
      errors.push(`Naga: ${stderr.split('\n').filter(l => l.includes('error:')).join('; ')}`);
    }
  }

  return errors;
}

function runValidationPipeline() {
  console.log('\n🔬 Running validation pipeline...');
  let hadError = false;

  try {
    execSync('node scripts/generate_shader_lists.js', { cwd: PROJECT_ROOT, stdio: 'inherit' });
    console.log('✅ generate_shader_lists.js passed');
  } catch (e) {
    console.error('❌ generate_shader_lists.js failed');
    hadError = true;
  }

  try {
    execSync('node scripts/check_duplicates.js', { cwd: PROJECT_ROOT, stdio: 'inherit' });
    console.log('✅ check_duplicates.js passed');
  } catch (e) {
    console.error('❌ check_duplicates.js failed');
    hadError = true;
  }

  return !hadError;
}

function printAgentManifest(queue, batchSize) {
  const pending = queue.items.filter(i => i.status === 'pending');
  const batch = pending.slice(0, batchSize);

  const manifest = batch.map(item => {
    const promptPath = path.join(PROMPTS_DIR, `${item.id}.md`);
    const prompt = fs.readFileSync(promptPath, 'utf8');
    return {
      id: item.id,
      agent_role: item.agent_role,
      prompt_length: prompt.length,
      prompt_file: promptPath,
    };
  });

  console.log('\n📋 Agent Dispatch Manifest (JSON):');
  console.log(JSON.stringify(manifest, null, 2));
}

async function main() {
  const opts = parseArgs();

  if (opts.help) {
    printHelp();
    return;
  }

  // Default to --prepare if no mode specified
  if (!opts.prepare && !opts.dispatch && !opts.agentDispatch) {
    opts.prepare = true;
  }

  console.log('═══════════════════════════════════════════════════════════════════════════════');
  console.log('  🚀 Shader Upgrade Swarm Orchestrator');
  console.log('═══════════════════════════════════════════════════════════════════════════════');

  const queue = loadQueue();
  const progress = loadProgress();

  console.log(`Queue version: ${queue.version}`);
  console.log(`Total items: ${queue.items.length}`);
  console.log(`Pending: ${queue.items.filter(i => i.status === 'pending').length}`);
  console.log(`Batch size: ${opts.batch}`);
  console.log(`Mode: ${opts.prepare ? 'PREPARE' : opts.dispatch ? 'DISPATCH' : 'AGENT-DISPATCH'}`);
  console.log('');

  const pending = queue.items.filter(i => i.status === 'pending');
  if (pending.length === 0) {
    console.log('✅ No pending shaders in queue.');
    return;
  }

  const batch = pending.slice(0, opts.batch);
  console.log(`Processing batch of ${batch.length} shader(s):`);
  batch.forEach(item => console.log(`  → ${item.id} (${item.agent_role})`));
  console.log('');

  // Step 1: Generate prompts for the batch
  let generated = 0;
  for (const item of batch) {
    try {
      const promptPath = writePrompt(item);
      console.log(`📝 Prompt generated: ${path.relative(PROJECT_ROOT, promptPath)}`);
      generated++;
    } catch (err) {
      console.error(`❌ Failed to generate prompt for ${item.id}: ${err.message}`);
    }
  }

  console.log(`\n✅ Generated ${generated}/${batch.length} prompt files in ${path.relative(PROJECT_ROOT, PROMPTS_DIR)}/`);

  // Step 2: Mode-specific handling
  if (opts.agentDispatch) {
    printAgentManifest(queue, opts.batch);
    return;
  }

  if (opts.dispatch) {
    const apiKey = process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      console.log('\n⚠️  No OPENAI_API_KEY or ANTHROPIC_API_KEY found in environment.');
      console.log('   Falling back to --prepare mode. Set an API key to use --dispatch.');
      return;
    }

    console.log('\n🚀 Dispatch mode: spawning parallel subagents...');
    console.log('   (Note: Full AI API dispatch requires a subagent worker implementation.');
    console.log('    For now, prompts are ready. Use --agent-dispatch to get a manifest for manual Agent-tool usage.)');
    // Placeholder: in a future iteration, spawn child processes that call the AI API.
  }

  // Step 3: Validation pipeline (only if something was actually modified)
  // For --prepare, we skip validation since no WGSL changed yet.
  if (opts.dispatch) {
    const valid = runValidationPipeline();
    if (valid) {
      console.log('\n✅ Validation pipeline passed.');
    } else {
      console.log('\n⚠️  Validation pipeline reported errors.');
    }
  }

  // Save progress
  progress.runs.push({
    timestamp: new Date().toISOString(),
    mode: opts.prepare ? 'prepare' : opts.dispatch ? 'dispatch' : 'agent-dispatch',
    batch: batch.map(b => b.id),
    prompts_generated: generated,
  });
  saveProgress(progress);

  console.log('\n🎉 Swarm step complete!');
  if (opts.prepare) {
    console.log(`   Review prompts in ${path.relative(PROJECT_ROOT, PROMPTS_DIR)}/`);
    console.log(`   Then run with --agent-dispatch to get a manifest for AI subagent spawning.`);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
