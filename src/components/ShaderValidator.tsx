/**
 * ShaderValidator.tsx
 *
 * Dev-tool page that sequentially tests every shader in the library for
 * WebGPU compilation and pipeline errors in complete isolation.
 *
 * Accessible via: ?validator  (handled in src/index.tsx)
 *
 * Quick mode  — bind-group static validation + shader module compilation
 *               + getCompilationInfo error check
 * Full mode   — everything in Quick + createComputePipeline + bind group
 *               creation (closest to real rendering)
 *
 * A single GPUDevice is shared for the entire run so we avoid per-shader
 * adapter re-requests (which are slow).  All resources created for Full mode
 * are destroyed immediately after the shader under test to keep memory flat.
 */

import React, { useState, useRef, useCallback } from 'react';
import { validateBindGroup, BindGroupValidationResult } from '../renderer/bindGroupValidator';
import '../styles/gold-glass-theme.css';

// ── Types ────────────────────────────────────────────────────────────────────

interface ShaderDef {
  id: string;
  name: string;
  url: string;
  category?: string;
}

export type ValidationStatus = 'pass' | 'fail' | 'warning' | 'pending';

export interface ValidationResult {
  id: string;
  name: string;
  url: string;
  category: string;
  status: ValidationStatus;
  error?: string;
  warnings: string[];
  compilationMessages: string[];
  durationMs: number;
}

type TestMode = 'quick' | 'full';

// ── Constants ────────────────────────────────────────────────────────────────

/** All shader-list JSON files in public/shader-lists/ */
const SHADER_LIST_FILES = [
  'image.json',
  'generative.json',
  'interactive-mouse.json',
  'interactive.json',
  'distortion.json',
  'simulation.json',
  'liquid-effects.json',
  'liquid.json',
  'artistic.json',
  'geometric.json',
  'hybrid.json',
  'advanced-hybrid.json',
  'visual-effects.json',
  'lighting-effects.json',
  'retro-glitch.json',
  'post-processing.json',
];

/** Internal resolution used for Full-mode GPU resources (kept small for speed) */
const VALIDATOR_RES = 256;

/** How many floats in the uniform buffer (matches WebGPURenderer) */
const UNIFORM_FLOATS = 212; // 12 + 50*4

/** Extra buffer size in floats (matches WebGPURenderer) */
const EXTRA_FLOATS = 256;

/** Plasma buffer minimum size in bytes */
const PLASMA_BYTES = 50 * 48;

/** History ring depth (opt-in binding 13) */
const HISTORY_DEPTH = 8;

// ── Helper: create full GPU resources for one test ───────────────────────────

interface TestResources {
  device: GPUDevice;
  bindGroupLayout: GPUBindGroupLayout;
  pipelineLayout: GPUPipelineLayout;
  textures: GPUTexture[];
  buffers: GPUBuffer[];
  samplers: GPUSampler[];
  bindGroup: GPUBindGroup;
}

function createTestResources(device: GPUDevice): TestResources {
  const V = GPUShaderStage.COMPUTE;
  const W = VALIDATOR_RES;

  const USAGE_RW =
    GPUTextureUsage.TEXTURE_BINDING |
    GPUTextureUsage.STORAGE_BINDING |
    GPUTextureUsage.COPY_DST |
    GPUTextureUsage.COPY_SRC;

  // Detect float32-filterable support
  const hasF32Filt = device.features.has('float32-filterable');
  const fST: GPUTextureSampleType = hasF32Filt ? 'float' : 'unfilterable-float';

  // Build bind group layout (mirrors WebGPURenderer.createComputeBindGroupLayout)
  const bindGroupLayout = device.createBindGroupLayout({
    label: 'validatorBGL',
    entries: [
      { binding:  0, visibility: V, sampler:        { type: 'filtering' } },
      { binding:  1, visibility: V, texture:        { sampleType: fST } },
      { binding:  2, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
      { binding:  3, visibility: V, buffer:         { type: 'uniform' } },
      { binding:  4, visibility: V, texture:        { sampleType: 'unfilterable-float' } },
      { binding:  5, visibility: V, sampler:        { type: 'non-filtering' } },
      { binding:  6, visibility: V, storageTexture: { access: 'write-only', format: 'r32float' } },
      { binding:  7, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
      { binding:  8, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
      { binding:  9, visibility: V, texture:        { sampleType: fST } },
      { binding: 10, visibility: V, buffer:         { type: 'storage' } },
      { binding: 11, visibility: V, sampler:        { type: 'comparison' } },
      { binding: 12, visibility: V, buffer:         { type: 'read-only-storage' } },
      { binding: 13, visibility: V, texture:        { sampleType: fST, viewDimension: '2d-array' } },
    ],
  });

  const pipelineLayout = device.createPipelineLayout({
    label: 'validatorPL',
    bindGroupLayouts: [bindGroupLayout],
  });

  // Create minimal textures
  const mkTex = (label: string, fmt: GPUTextureFormat, layers = 1) =>
    device.createTexture({
      label,
      size: layers > 1 ? { width: W, height: W, depthOrArrayLayers: layers } : [W, W],
      format: fmt,
      usage: USAGE_RW,
    });

  const readTex      = mkTex('val-readTex',      'rgba32float');
  const writeTex     = mkTex('val-writeTex',     'rgba32float');
  const dataTexA     = mkTex('val-dataTexA',     'rgba32float');
  const dataTexB     = mkTex('val-dataTexB',     'rgba32float');
  const dataTexC     = mkTex('val-dataTexC',     'rgba32float');
  const historyTex   = mkTex('val-historyTex',   'rgba32float', HISTORY_DEPTH);
  const depthRead    = mkTex('val-depthRead',    'r32float');
  const depthWrite   = mkTex('val-depthWrite',   'r32float');

  const textures = [readTex, writeTex, dataTexA, dataTexB, dataTexC, historyTex, depthRead, depthWrite];

  // Samplers
  const filterSampler = device.createSampler({
    label: 'val-filterSampler',
    magFilter: 'linear', minFilter: 'linear',
    addressModeU: 'repeat', addressModeV: 'repeat',
  });
  const nearestSampler = device.createSampler({
    label: 'val-nearestSampler',
    magFilter: 'nearest', minFilter: 'nearest',
  });
  const compSampler = device.createSampler({
    label: 'val-compSampler',
    compare: 'less',
  });
  const samplers = [filterSampler, nearestSampler, compSampler];

  // Buffers
  const uniformBuf = device.createBuffer({
    label: 'val-uniformBuf',
    size: UNIFORM_FLOATS * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  const extraBuf = device.createBuffer({
    label: 'val-extraBuf',
    size: EXTRA_FLOATS * 4,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });
  const plasmaBuf = device.createBuffer({
    label: 'val-plasmaBuf',
    size: Math.max(PLASMA_BYTES, 16),
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });
  const buffers = [uniformBuf, extraBuf, plasmaBuf];

  // Bind group
  const bindGroup = device.createBindGroup({
    label: 'validatorBG',
    layout: bindGroupLayout,
    entries: [
      { binding:  0, resource: filterSampler },
      { binding:  1, resource: readTex.createView() },
      { binding:  2, resource: writeTex.createView() },
      { binding:  3, resource: { buffer: uniformBuf } },
      { binding:  4, resource: depthRead.createView() },
      { binding:  5, resource: nearestSampler },
      { binding:  6, resource: depthWrite.createView() },
      { binding:  7, resource: dataTexA.createView() },
      { binding:  8, resource: dataTexB.createView() },
      { binding:  9, resource: dataTexC.createView() },
      { binding: 10, resource: { buffer: extraBuf } },
      { binding: 11, resource: compSampler },
      { binding: 12, resource: { buffer: plasmaBuf } },
      {
        binding: 13,
        resource: historyTex.createView({
          dimension: '2d-array',
          baseArrayLayer: 0,
          arrayLayerCount: HISTORY_DEPTH,
        }),
      },
    ],
  });

  return { device, bindGroupLayout, pipelineLayout, textures, buffers, samplers, bindGroup };
}

function destroyTestResources(res: TestResources): void {
  for (const t of res.textures) t.destroy();
  for (const b of res.buffers)  b.destroy();
  // Samplers and bind groups have no explicit destroy in WebGPU
}

// ── Core test function ────────────────────────────────────────────────────────

async function testShader(
  device: GPUDevice,
  shader: ShaderDef,
  mode: TestMode,
): Promise<ValidationResult> {
  const t0 = performance.now();
  const result: ValidationResult = {
    id: shader.id,
    name: shader.name,
    url: shader.url,
    category: shader.category ?? '',
    status: 'pass',
    warnings: [],
    compilationMessages: [],
    durationMs: 0,
  };

  // 1. Fetch WGSL source
  let wgsl: string;
  try {
    const resp = await fetch(shader.url);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    wgsl = await resp.text();
    if (!wgsl.trim()) throw new Error('Empty WGSL file');
  } catch (e: any) {
    result.status = 'fail';
    result.error = `Fetch failed: ${e?.message ?? String(e)}`;
    result.durationMs = performance.now() - t0;
    return result;
  }

  // 2. Static bind-group validation
  let bgResult: BindGroupValidationResult;
  try {
    bgResult = validateBindGroup(shader.id, wgsl);
  } catch (e: any) {
    result.status = 'fail';
    result.error = `Static validation threw: ${e?.message ?? String(e)}`;
    result.durationMs = performance.now() - t0;
    return result;
  }

  if (!bgResult.valid) {
    result.status = 'fail';
    result.error = bgResult.errors.join('; ');
    result.durationMs = performance.now() - t0;
    return result;
  }
  if (bgResult.warnings.length > 0) {
    result.warnings.push(...bgResult.warnings);
  }

  // 3. Create shader module + gather compilation info
  let shaderModule: GPUShaderModule;
  try {
    shaderModule = device.createShaderModule({ label: shader.id, code: wgsl });
  } catch (e: any) {
    result.status = 'fail';
    result.error = `createShaderModule threw: ${e?.message ?? String(e)}`;
    result.durationMs = performance.now() - t0;
    return result;
  }

  try {
    const info = await shaderModule.getCompilationInfo();
    const errors   = info.messages.filter(m => m.type === 'error');
    const warnings = info.messages.filter(m => m.type === 'warning');
    const infos    = info.messages.filter(m => m.type === 'info');

    for (const msg of errors) {
      result.compilationMessages.push(
        `ERROR line ${msg.lineNum}:${msg.linePos} — ${msg.message}`
      );
    }
    for (const msg of warnings) {
      result.compilationMessages.push(
        `WARNING line ${msg.lineNum}:${msg.linePos} — ${msg.message}`
      );
      result.warnings.push(msg.message);
    }
    for (const msg of infos) {
      result.compilationMessages.push(`INFO — ${msg.message}`);
    }

    if (errors.length > 0) {
      result.status = 'fail';
      result.error = errors.map(e => `Line ${e.lineNum}: ${e.message}`).join('; ');
      result.durationMs = performance.now() - t0;
      return result;
    }
  } catch (e: any) {
    // getCompilationInfo is optional; some environments may not support it
    result.warnings.push(`getCompilationInfo unavailable: ${e?.message ?? String(e)}`);
  }

  // 4. Full mode: pipeline creation + bind group
  if (mode === 'full') {
    const resources = createTestResources(device);
    try {
      const pipeline = device.createComputePipeline({
        label: shader.id,
        layout: resources.pipelineLayout,
        compute: { module: shaderModule, entryPoint: 'main' },
      });

      // Verify the bind group is compatible by creating an encoder and setting it
      const encoder = device.createCommandEncoder({ label: `val-${shader.id}` });
      const pass = encoder.beginComputePass({ label: `val-pass-${shader.id}` });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, resources.bindGroup);
      pass.dispatchWorkgroups(1, 1, 1);
      pass.end();
      // Submit — errors surface via the device error scope or uncaptured error event
      device.queue.submit([encoder.finish()]);
      await device.queue.onSubmittedWorkDone();
    } catch (e: any) {
      result.status = 'fail';
      result.error = `Pipeline/dispatch failed: ${e?.message ?? String(e)}`;
      result.durationMs = performance.now() - t0;
      destroyTestResources(resources);
      return result;
    }
    destroyTestResources(resources);
  }

  // 5. Determine final status
  if (result.warnings.length > 0 && result.status === 'pass') {
    result.status = 'warning';
  }

  result.durationMs = performance.now() - t0;
  return result;
}

// ── Main component ────────────────────────────────────────────────────────────

const ShaderValidator: React.FC = () => {
  const [mode, setMode] = useState<TestMode>('quick');
  const [running, setRunning] = useState(false);
  const [progress, setProgress] = useState(0);
  const [total, setTotal] = useState(0);
  const [currentShader, setCurrentShader] = useState('');
  const [results, setResults] = useState<ValidationResult[]>([]);
  const [gpuError, setGpuError] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | 'fail' | 'warning' | 'pass'>('all');
  const [expandedRow, setExpandedRow] = useState<string | null>(null);
  const abortRef = useRef(false);

  const run = useCallback(async () => {
    setRunning(true);
    setResults([]);
    setProgress(0);
    setCurrentShader('');
    setGpuError(null);
    abortRef.current = false;

    // 1. Initialise WebGPU
    if (!navigator.gpu) {
      setGpuError(
        'WebGPU is not available. Please use Chrome 113+, Edge 113+, or Firefox Nightly with ' +
        'dom.webgpu.enabled flag. HTTPS or localhost is required.'
      );
      setRunning(false);
      return;
    }
    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) {
      setGpuError(
        'No GPU adapter found. This may occur if WebGPU is disabled in browser settings, ' +
        'your GPU does not support WebGPU, or you are running in a headless/virtual environment.'
      );
      setRunning(false);
      return;
    }

    const wantFeatures: GPUFeatureName[] = [];
    if (adapter.features.has('float32-filterable')) wantFeatures.push('float32-filterable');

    let device: GPUDevice;
    try {
      device = await adapter.requestDevice({
        label: 'ShaderValidatorDevice',
        requiredFeatures: wantFeatures,
      });
    } catch (e: any) {
      setGpuError(`requestDevice failed: ${e?.message ?? String(e)}`);
      setRunning(false);
      return;
    }

    device.addEventListener('uncapturederror', (ev) => {
      console.warn('[ShaderValidator] Uncaptured GPU error:', (ev as GPUUncapturedErrorEvent).error);
    });

    // 2. Load all shader lists
    const allShaders: ShaderDef[] = [];
    for (const file of SHADER_LIST_FILES) {
      try {
        const resp = await fetch(`shader-lists/${file}`);
        if (!resp.ok) continue;
        const list: ShaderDef[] = await resp.json();
        const category = file.replace('.json', '');
        for (const s of list) {
          allShaders.push({ ...s, category: s.category ?? category });
        }
      } catch {
        // Skip missing list files silently
      }
    }

    // Deduplicate by id (same shader may appear in multiple lists)
    const seen = new Set<string>();
    const unique = allShaders.filter(s => {
      if (seen.has(s.id)) return false;
      seen.add(s.id);
      return true;
    });

    setTotal(unique.length);

    // 3. Test shaders sequentially
    const collected: ValidationResult[] = [];
    for (let i = 0; i < unique.length; i++) {
      if (abortRef.current) break;

      const shader = unique[i];
      setCurrentShader(`[${i + 1}/${unique.length}] ${shader.name}`);

      // Use GPU error scopes to capture pipeline errors in full mode
      if (mode === 'full') {
        device.pushErrorScope('validation');
        device.pushErrorScope('internal');
      }

      const result = await testShader(device, shader, mode);

      if (mode === 'full') {
        const internalErr  = await device.popErrorScope();
        const validationErr = await device.popErrorScope();
        const gpuErrMsg = internalErr?.message ?? validationErr?.message;
        if (gpuErrMsg && result.status !== 'fail') {
          result.status = 'fail';
          result.error = (result.error ? result.error + '; ' : '') + `GPU error: ${gpuErrMsg}`;
        }
      }

      collected.push(result);
      setProgress(i + 1);
      // Yield to React so the UI can update
      setResults([...collected]);
      await new Promise(r => setTimeout(r, 0));
    }

    device.destroy();
    setCurrentShader('');
    setRunning(false);
  }, [mode]);

  const stop = useCallback(() => {
    abortRef.current = true;
  }, []);

  const exportReport = useCallback(() => {
    const report = {
      generatedAt: new Date().toISOString(),
      mode,
      total: results.length,
      passed:   results.filter(r => r.status === 'pass').length,
      warnings: results.filter(r => r.status === 'warning').length,
      failed:   results.filter(r => r.status === 'fail').length,
      results,
    };
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `shader-validation-report-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }, [results, mode]);

  // Summary counts
  const passed   = results.filter(r => r.status === 'pass').length;
  const warnings = results.filter(r => r.status === 'warning').length;
  const failed   = results.filter(r => r.status === 'fail').length;
  const pct = total > 0 ? Math.round((progress / total) * 100) : 0;

  const filtered = results.filter(r =>
    filter === 'all' ? true : r.status === filter
  );

  const statusIcon = (s: ValidationStatus) => {
    if (s === 'pass')    return '✅';
    if (s === 'fail')    return '❌';
    if (s === 'warning') return '⚠️';
    return '⏳';
  };

  return (
    <div style={styles.page}>
      {/* Header */}
      <div style={styles.header}>
        <h1 style={styles.title}>🔍 Shader Validator</h1>
        <p style={styles.subtitle}>
          Sequentially tests all shaders for WebGPU compilation &amp; pipeline errors
        </p>
      </div>

      {/* Controls */}
      <div style={styles.card}>
        <div style={styles.controlRow}>
          {/* Mode selector */}
          <div style={styles.modeGroup}>
            <span style={styles.label}>Mode:</span>
            {(['quick', 'full'] as TestMode[]).map(m => (
              <button
                key={m}
                style={mode === m ? styles.modeButtonActive : styles.modeButton}
                onClick={() => !running && setMode(m)}
                disabled={running}
                title={
                  m === 'quick'
                    ? 'Static validation + shader module compilation only (fast)'
                    : 'Static validation + shader module + full pipeline creation + dispatch (slower, closer to real usage)'
                }
              >
                {m === 'quick' ? '⚡ Quick' : '🔬 Full'}
              </button>
            ))}
          </div>

          {/* Action buttons */}
          <div style={styles.modeGroup}>
            {!running ? (
              <button style={styles.runButton} onClick={run}>
                ▶ Run
              </button>
            ) : (
              <button style={styles.stopButton} onClick={stop}>
                ⏹ Stop
              </button>
            )}
            {results.length > 0 && !running && (
              <button style={styles.exportButton} onClick={exportReport}>
                ⬇ Export JSON
              </button>
            )}
          </div>
        </div>

        {/* Mode description */}
        <p style={styles.modeDesc}>
          {mode === 'quick'
            ? '⚡ Quick: Static bind-group validation + createShaderModule + getCompilationInfo'
            : '🔬 Full: Quick + createComputePipeline + bind group + GPU dispatch (256×256)'}
        </p>
      </div>

      {/* GPU error */}
      {gpuError && (
        <div style={styles.errorBanner}>
          ❌ WebGPU Error: {gpuError}
        </div>
      )}

      {/* Progress */}
      {(running || progress > 0) && (
        <div style={styles.card}>
          <div style={styles.progressHeader}>
            <span style={styles.label}>
              {running ? `Testing: ${currentShader}` : `Done — ${progress}/${total}`}
            </span>
            <span style={styles.pctLabel}>{pct}%</span>
          </div>
          <div style={styles.progressTrack}>
            <div style={{ ...styles.progressFill, width: `${pct}%` }} />
          </div>
          {/* Summary pills */}
          <div style={styles.summaryRow}>
            <span style={styles.pillPass}>✅ {passed} pass</span>
            <span style={styles.pillWarn}>⚠️ {warnings} warn</span>
            <span style={styles.pillFail}>❌ {failed} fail</span>
          </div>
        </div>
      )}

      {/* Results table */}
      {results.length > 0 && (
        <div style={styles.card}>
          {/* Filter tabs */}
          <div style={styles.filterRow}>
            {(['all', 'pass', 'warning', 'fail'] as const).map(f => (
              <button
                key={f}
                style={filter === f ? styles.filterTabActive : styles.filterTab}
                onClick={() => setFilter(f)}
              >
                {f === 'all'     ? `All (${results.length})`     : ''}
                {f === 'pass'    ? `✅ Pass (${passed})`          : ''}
                {f === 'warning' ? `⚠️ Warn (${warnings})`        : ''}
                {f === 'fail'    ? `❌ Fail (${failed})`           : ''}
              </button>
            ))}
          </div>

          {/* Table */}
          <div style={styles.tableWrap}>
            <table style={styles.table}>
              <thead>
                <tr>
                  <th style={styles.th}>#</th>
                  <th style={styles.th}>Status</th>
                  <th style={styles.th}>Shader</th>
                  <th style={styles.th}>Category</th>
                  <th style={styles.th}>ms</th>
                  <th style={styles.th}>Error / Warnings</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((r, idx) => (
                  <React.Fragment key={r.id}>
                    <tr
                      style={rowStyle(r.status)}
                      onClick={() => setExpandedRow(expandedRow === r.id ? null : r.id)}
                    >
                      <td style={styles.td}>{idx + 1}</td>
                      <td style={{ ...styles.td, textAlign: 'center' }}>{statusIcon(r.status)}</td>
                      <td style={styles.td}>
                        <span style={styles.shaderId}>{r.id}</span>
                        <span style={styles.shaderName}> {r.name}</span>
                      </td>
                      <td style={styles.td}>{r.category}</td>
                      <td style={styles.td}>{r.durationMs.toFixed(1)}</td>
                      <td style={styles.td}>
                        {r.error && <span style={styles.errorText}>{r.error}</span>}
                        {!r.error && r.warnings.length > 0 && (
                          <span style={styles.warnText}>{r.warnings[0]}</span>
                        )}
                      </td>
                    </tr>
                    {expandedRow === r.id && (
                      <tr style={styles.expandedRow}>
                        <td colSpan={6} style={styles.expandedCell}>
                          <div style={styles.expandedContent}>
                            <div><strong>URL:</strong> {r.url}</div>
                            {r.error && (
                              <div style={{ marginTop: 6 }}>
                                <strong>Error:</strong>
                                <pre style={styles.pre}>{r.error}</pre>
                              </div>
                            )}
                            {r.warnings.length > 0 && (
                              <div style={{ marginTop: 6 }}>
                                <strong>Warnings:</strong>
                                <pre style={styles.pre}>{r.warnings.join('\n')}</pre>
                              </div>
                            )}
                            {r.compilationMessages.length > 0 && (
                              <div style={{ marginTop: 6 }}>
                                <strong>Compilation messages:</strong>
                                <pre style={styles.pre}>{r.compilationMessages.join('\n')}</pre>
                              </div>
                            )}
                          </div>
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};

// ── Styles ────────────────────────────────────────────────────────────────────

const styles: Record<string, React.CSSProperties> = {
  page: {
    minHeight: '100vh',
    background: 'var(--color-bg-dark, #0a0a0f)',
    color: 'var(--color-text-primary, #fff)',
    fontFamily: 'var(--font-family, Inter, system-ui, sans-serif)',
    padding: '24px',
    boxSizing: 'border-box',
  },
  header: {
    marginBottom: 24,
  },
  title: {
    fontSize: 'var(--font-size-2xl, 2rem)',
    fontWeight: 700,
    color: 'var(--color-primary-gold, #FFD700)',
    margin: '0 0 8px',
    letterSpacing: 'var(--letter-spacing-header, 0.5px)',
  },
  subtitle: {
    color: 'var(--color-text-secondary, rgba(255,255,255,0.7))',
    margin: 0,
    fontSize: 'var(--font-size-sm, 0.875rem)',
  },
  card: {
    background: 'var(--color-glass-bg, rgba(20,20,30,0.6))',
    backdropFilter: 'blur(12px)',
    border: '1px solid var(--color-glass-border, rgba(255,215,0,0.2))',
    borderRadius: 12,
    padding: 20,
    marginBottom: 16,
    boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
  },
  controlRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    gap: 12,
  },
  modeGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  label: {
    color: 'var(--color-text-secondary, rgba(255,255,255,0.7))',
    fontSize: 'var(--font-size-sm, 0.875rem)',
  },
  modeButton: {
    background: 'transparent',
    border: '1px solid rgba(255,215,0,0.3)',
    borderRadius: 8,
    color: 'rgba(255,215,0,0.7)',
    padding: '8px 16px',
    cursor: 'pointer',
    fontSize: 'var(--font-size-sm, 0.875rem)',
    transition: 'all 0.2s',
  },
  modeButtonActive: {
    background: 'linear-gradient(135deg, #FFD700 0%, #D4AF37 50%, #B8860B 100%)',
    border: 'none',
    borderRadius: 8,
    color: '#0a0a0f',
    padding: '8px 16px',
    cursor: 'pointer',
    fontSize: 'var(--font-size-sm, 0.875rem)',
    fontWeight: 600,
    boxShadow: '0 4px 16px rgba(255,215,0,0.3)',
  },
  runButton: {
    background: 'linear-gradient(135deg, #FFD700 0%, #D4AF37 50%, #B8860B 100%)',
    border: 'none',
    borderRadius: 8,
    color: '#0a0a0f',
    padding: '10px 24px',
    cursor: 'pointer',
    fontWeight: 700,
    fontSize: 'var(--font-size-base, 1rem)',
    boxShadow: '0 4px 16px rgba(255,215,0,0.3)',
  },
  stopButton: {
    background: 'rgba(200,60,60,0.8)',
    border: '1px solid rgba(255,100,100,0.4)',
    borderRadius: 8,
    color: '#fff',
    padding: '10px 24px',
    cursor: 'pointer',
    fontWeight: 700,
    fontSize: 'var(--font-size-base, 1rem)',
  },
  exportButton: {
    background: 'rgba(20,20,30,0.8)',
    border: '1px solid rgba(255,215,0,0.3)',
    borderRadius: 8,
    color: '#FFD700',
    padding: '10px 20px',
    cursor: 'pointer',
    fontWeight: 600,
    fontSize: 'var(--font-size-sm, 0.875rem)',
  },
  modeDesc: {
    margin: '12px 0 0',
    fontSize: 'var(--font-size-xs, 0.75rem)',
    color: 'var(--color-text-muted, rgba(255,255,255,0.5))',
  },
  errorBanner: {
    background: 'rgba(180,40,40,0.3)',
    border: '1px solid rgba(255,80,80,0.4)',
    borderRadius: 8,
    padding: '12px 16px',
    marginBottom: 16,
    color: '#ff8080',
  },
  progressHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  pctLabel: {
    color: 'var(--color-primary-gold, #FFD700)',
    fontWeight: 600,
  },
  progressTrack: {
    height: 6,
    background: 'rgba(255,255,255,0.1)',
    borderRadius: 9999,
    overflow: 'hidden',
    marginBottom: 12,
  },
  progressFill: {
    height: '100%',
    background: 'linear-gradient(90deg, #FFD700, #B8860B)',
    borderRadius: 9999,
    transition: 'width 0.1s linear',
  },
  summaryRow: {
    display: 'flex',
    gap: 12,
    flexWrap: 'wrap',
  },
  pillPass: {
    background: 'rgba(40,160,80,0.3)',
    border: '1px solid rgba(80,200,100,0.4)',
    borderRadius: 9999,
    padding: '4px 12px',
    fontSize: 'var(--font-size-xs, 0.75rem)',
    color: '#80ff80',
  },
  pillWarn: {
    background: 'rgba(180,140,40,0.3)',
    border: '1px solid rgba(255,200,60,0.4)',
    borderRadius: 9999,
    padding: '4px 12px',
    fontSize: 'var(--font-size-xs, 0.75rem)',
    color: '#ffd080',
  },
  pillFail: {
    background: 'rgba(160,40,40,0.3)',
    border: '1px solid rgba(255,80,80,0.4)',
    borderRadius: 9999,
    padding: '4px 12px',
    fontSize: 'var(--font-size-xs, 0.75rem)',
    color: '#ff8080',
  },
  filterRow: {
    display: 'flex',
    gap: 8,
    marginBottom: 16,
    flexWrap: 'wrap',
  },
  filterTab: {
    background: 'transparent',
    border: '1px solid rgba(255,215,0,0.2)',
    borderRadius: 20,
    color: 'rgba(255,255,255,0.6)',
    padding: '5px 14px',
    cursor: 'pointer',
    fontSize: 'var(--font-size-xs, 0.75rem)',
  },
  filterTabActive: {
    background: 'rgba(255,215,0,0.15)',
    border: '1px solid rgba(255,215,0,0.5)',
    borderRadius: 20,
    color: '#FFD700',
    padding: '5px 14px',
    cursor: 'pointer',
    fontSize: 'var(--font-size-xs, 0.75rem)',
    fontWeight: 600,
  },
  tableWrap: {
    overflowX: 'auto',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: 'var(--font-size-xs, 0.75rem)',
  },
  th: {
    textAlign: 'left',
    padding: '8px 12px',
    borderBottom: '1px solid rgba(255,215,0,0.2)',
    color: 'var(--color-primary-gold, #FFD700)',
    fontWeight: 600,
    whiteSpace: 'nowrap',
  },
  td: {
    padding: '7px 12px',
    borderBottom: '1px solid rgba(255,255,255,0.06)',
    verticalAlign: 'top',
    maxWidth: 340,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  shaderId: {
    fontFamily: 'var(--font-family-mono, monospace)',
    color: 'rgba(255,215,0,0.8)',
    fontSize: '0.7rem',
  },
  shaderName: {
    color: 'rgba(255,255,255,0.85)',
  },
  errorText: {
    color: '#ff8080',
    fontFamily: 'var(--font-family-mono, monospace)',
    fontSize: '0.7rem',
  },
  warnText: {
    color: '#ffd080',
    fontFamily: 'var(--font-family-mono, monospace)',
    fontSize: '0.7rem',
  },
  expandedRow: {
    background: 'rgba(0,0,0,0.3)',
  },
  expandedCell: {
    padding: '12px 16px',
    borderBottom: '1px solid rgba(255,255,255,0.08)',
  },
  expandedContent: {
    fontSize: 'var(--font-size-xs, 0.75rem)',
    color: 'rgba(255,255,255,0.75)',
  },
  pre: {
    margin: '4px 0 0',
    padding: '8px',
    background: 'rgba(0,0,0,0.4)',
    borderRadius: 6,
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-all',
    fontFamily: 'var(--font-family-mono, monospace)',
    fontSize: '0.7rem',
    color: 'rgba(255,255,255,0.7)',
    maxHeight: 200,
    overflowY: 'auto',
  },
};

function rowStyle(status: ValidationStatus): React.CSSProperties {
  const base: React.CSSProperties = {
    cursor: 'pointer',
    transition: 'background 0.15s',
  };
  if (status === 'fail')    return { ...base, background: 'rgba(160,40,40,0.15)' };
  if (status === 'warning') return { ...base, background: 'rgba(160,140,0,0.1)' };
  return base;
}

export default ShaderValidator;
