import React, { useState, useCallback, useRef, useMemo, useEffect } from 'react';
import { ShaderEntry } from '../renderer/types';
import { fetchShaderWgsl } from '../utils/fetchShaderWgsl';
import { getShaderCompileService, type CompileMessageLike, type ShaderCompileService } from '../utils/shaderCompileService';
import { getDeviceGeneration } from '../renderer/deviceRegistry';
import { WebGpuProbeFailureOverlay } from './WebGpuProbeFailureOverlay';
import type { WebGpuProbeSerializable } from '../renderer/webgpuBootProbe';
import {
  ThumbnailHost,
  ThumbnailState,
  ThumbnailFreshness,
  ThumbnailManifest,
  RepoThumbnailWriter,
  CaptureResult,
  CaptureSessionState,
  DEFAULT_CAPTURE_OPTIONS,
  captureShaderThumbnail,
  loadThumbnailState,
  needsThumbnail,
  freshnessFor,
  summarizeFreshness,
  pickRepoWriter,
  isRepoWriterSupported,
} from '../services/thumbnailBatch';

type ScanScope = 'changed' | 'all';
/** off: compile/params only · check: also render each shader and flag black/magenta frames · save: check + write thumbnails */
type ScanRenderMode = 'off' | 'check' | 'save';

interface ShaderParam {
  id: string;
  name: string;
  default: number;
  min: number;
  max: number;
  step?: number;
  mapping?: string;
}

interface ShaderScanResult {
  id: string;
  name: string;
  url: string;
  category: string;
  status: 'pending' | 'loading' | 'success' | 'error' | 'skipped';
  errorMessage?: string;
  compileTimeMs?: number;
  params?: ShaderParam[];
  paramStatus?: 'valid' | 'invalid' | 'no-params';
  paramErrors?: string[];
  thumb?: ThumbnailFreshness;
  render?: 'pending' | 'ok' | 'saved' | 'failed';
  lastUpgraded?: string;
}

interface ShaderScannerProps {
  shaders: ShaderEntry[];
  isOpen: boolean;
  onClose: () => void;
  onTestShader?: (shaderId: string, testValues: number[]) => Promise<{ success: boolean; error?: string }>;
  /** Enables the render check + thumbnail capture phase. */
  thumbnailHost?: ThumbnailHost;
}

// Shaders are already complete WGSL files with all necessary declarations
// We compile them directly without wrapping
const prepareShaderCode = (code: string): string => {
  // Check if shader already has the standard header
  if (code.includes('@group(0) @binding(0)') && code.includes('struct Uniforms')) {
    // Shader is complete, use as-is
    return code;
  }
  
  // If shader is missing bindings, add them (legacy support)
  const needsBindings = !code.includes('@group(0) @binding(0)');
  const needsUniforms = !code.includes('struct Uniforms');
  
  if (!needsBindings && !needsUniforms) {
    return code;
  }
  
  // Minimal wrapper for incomplete shaders
  const bindings = needsBindings ? `
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
` : '';

  const uniforms = needsUniforms ? `
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
` : '';

  return bindings + uniforms + code;
};

/**
 * Compile on whichever renderer device is current. Resolved per shader, not per scan: a
 * device loss or recovery mid-scan replaces it (registry generation), and a result from
 * a device that went away while compiling is retried once on the new one.
 */
async function compileOnRendererDevice(id: string, code: string): Promise<CompileMessageLike[]> {
  for (let attempt = 0; ; attempt++) {
    const compiler = getShaderCompileService();
    if (!compiler) throw new Error('Renderer GPUDevice unavailable (lost or recovering)');
    const generation = getDeviceGeneration();
    try {
      const messages = await compiler.compile(id, code);
      if (attempt > 0 || getDeviceGeneration() === generation) return messages;
    } catch (e) {
      if (attempt > 0 || getDeviceGeneration() === generation) throw e;
    }
  }
}

function resolveProbeFailure(): WebGpuProbeSerializable | null {
  const probe = window.webgpuProbe;
  if (!probe || probe.ok !== true) {
    return (
      probe ?? {
        ok: false,
        finishedAt: new Date().toISOString(),
        userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
        userAgentBrands: [],
        attempts: [],
        lastError: 'WebGPU boot probe has not succeeded',
        failedStage: 'requestAdapter',
      }
    );
  }
  if (!getShaderCompileService()) {
    return {
      ...probe,
      ok: false,
      lastError:
        'Renderer GPUDevice unavailable — WebGPU renderer must be active (page device or render worker)',
      failedStage: 'requestDevice',
    };
  }
  return null;
}

export const ShaderScanner: React.FC<ShaderScannerProps> = ({ shaders, isOpen, onClose, onTestShader, thumbnailHost }) => {
  const [results, setResults] = useState<ShaderScanResult[]>([]);
  const [isScanning, setIsScanning] = useState(false);
  const [scanMode, setScanMode] = useState<'compile' | 'params' | 'both'>('both');
  const [progress, setProgress] = useState(0);
  const [showParamDetails, setShowParamDetails] = useState<string | null>(null);
  const abortRef = useRef(false);

  // ── Thumbnail batch state ──────────────────────────────────────────────────
  const [scope, setScope] = useState<ScanScope>('changed');
  const [renderMode, setRenderMode] = useState<ScanRenderMode>(thumbnailHost ? 'save' : 'off');
  const [thumbState, setThumbState] = useState<ThumbnailState | null>(null);
  const [writer, setWriter] = useState<RepoThumbnailWriter | null>(null);
  const [phase, setPhase] = useState<'compile' | 'render' | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    void loadThumbnailState().then((state) => {
      if (cancelled) return;
      setThumbState((prev) => (prev && writer ? { ...state, manifest: prev.manifest } : state));
      if (!state.hashes) {
        setNotice('thumbnails/source-hashes.json not found — run `npm run build:source-hashes` (prestart does this) to detect changed shaders.');
      }
    });
    return () => { cancelled = true; };
  }, [isOpen, writer]);

  const changedShaders = useMemo(
    () => (thumbState ? shaders.filter((s) => needsThumbnail(s.id, thumbState)) : shaders),
    [shaders, thumbState],
  );
  const targets = scope === 'all' ? shaders : changedShaders;
  const freshSummary = useMemo(
    () => (thumbState ? summarizeFreshness(shaders.map((s) => s.id), thumbState) : null),
    [shaders, thumbState],
  );

  const updateResult = useCallback((id: string, patch: Partial<ShaderScanResult>) => {
    setResults((prev) => prev.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  }, []);

  const chooseRepoFolder = useCallback(async () => {
    try {
      const w = await pickRepoWriter();
      const manifest = await w.readManifest();
      setWriter(w);
      setThumbState(await loadThumbnailState(manifest));
      setNotice(`Saving thumbnails to ${w.label}${w.canWriteReports ? ' (failures → reports/thumbnail-failures-inapp.json)' : ''}`);
    } catch (e) {
      if ((e as DOMException)?.name === 'AbortError') return;
      setNotice(e instanceof Error ? e.message : String(e));
    }
  }, []);

  const probeFailure = useMemo(() => (isOpen ? resolveProbeFailure() : null), [isOpen]);
  const gpuReady = probeFailure == null;

  // Validate shader parameters from JSON definition
  const validateParams = (params: any[]): { valid: boolean; errors: string[]; normalized: ShaderParam[] } => {
    const errors: string[] = [];
    const normalized: ShaderParam[] = [];
    
    if (!params || params.length === 0) {
      return { valid: true, errors: [], normalized: [] };
    }
    
    for (const param of params) {
      // Check required fields
      if (!param.id) errors.push('Missing param id');
      if (!param.name) errors.push('Missing param name');
      
      // Validate ranges
      const min = param.min ?? 0;
      const max = param.max ?? 1;
      const defaultVal = param.default ?? 0.5;
      
      if (min >= max) errors.push(`Invalid range: min(${min}) >= max(${max})`);
      if (defaultVal < min || defaultVal > max) {
        errors.push(`Default value ${defaultVal} out of range [${min}, ${max}]`);
      }
      
      normalized.push({
        id: param.id || 'unnamed',
        name: param.name || 'Unnamed',
        default: defaultVal,
        min,
        max,
        step: param.step,
        mapping: param.mapping
      });
    }
    
    return { valid: errors.length === 0, errors, normalized };
  };

  const runScan = useCallback(async () => {
    const doCompileCheck = scanMode === 'compile' || scanMode === 'both';
    const doParamCheck = scanMode === 'params' || scanMode === 'both';
    
    let compiler: ShaderCompileService | null = null;
    let supportsSubgroups = false;
    
    if (doCompileCheck) {
      compiler = getShaderCompileService();
      if (!compiler) {
        alert('Renderer GPUDevice unavailable — WebGPU renderer must be active');
        return;
      }
      supportsSubgroups = compiler.supportsSubgroups;
    }

    if (renderMode === 'save' && !writer) {
      setNotice('Choose the repo folder before saving thumbnails.');
      return;
    }
    setIsScanning(true);
    setPhase('compile');
    setProgress(0);
    abortRef.current = false;
    const compileOk = new Set<string>();
    
    // Initialize results with param info if available
    const initialResults: ShaderScanResult[] = targets.map(s => ({
      id: s.id,
      name: s.name,
      url: s.url,
      category: s.category,
      status: 'pending',
      params: s.params,
      paramStatus: s.params && s.params.length > 0 ? 'valid' : 'no-params',
      thumb: thumbState ? freshnessFor(s.id, thumbState) : undefined,
      lastUpgraded: thumbState?.hashes?.upgrades[s.id]?.date,
    }));
    setResults(initialResults);

    const errors: ShaderScanResult[] = [];
    const batchSize = 3; // Smaller batch for more reliable testing

    for (let i = 0; i < targets.length; i += batchSize) {
      if (abortRef.current) break;

      const batch = targets.slice(i, i + batchSize);
      const batchPromises = batch.map(async (shader, batchIndex) => {
        const index = i + batchIndex;


        const patchResult = (patch: Partial<ShaderScanResult>) => setResults(prev => {
          const current = prev[index];
          if (!current) return prev;
          const updated = [...prev];
          updated[index] = { ...current, ...patch };
          return updated;
        });

        // Update status to loading
        patchResult({ status: 'loading' });

        const startTime = performance.now();
        let compileError: string | undefined;
        let paramValidation = { valid: true, errors: [] as string[], normalized: [] as ShaderParam[] };
        
        try {
          // Subgroup variants need the same device features as WebGPURenderer.
          if (shader.id.endsWith('-sg') && !supportsSubgroups) {
            patchResult({
              status: 'skipped',
              errorMessage: 'Subgroup variant requires subgroups GPU feature',
              paramStatus: shader.params && shader.params.length > 0 ? 'valid' : 'no-params',
            });
            return;
          }

          // Fetch via multi-host fallback (local → CDN → storage API).
          const code = await fetchShaderWgsl(shader.id, shader.url);
          if (!code) {
            throw new Error('Failed to fetch shader source from all known hosts');
          }
          
          // Skip if not a compute shader
          if (!code.includes('@compute')) {
            patchResult({
              status: 'skipped',
              errorMessage: 'Not a compute shader',
              paramStatus: 'no-params'
            });
            return;
          }

          // Validate parameters from JSON
          if (doParamCheck && shader.params) {
            paramValidation = validateParams(shader.params);
          }

          // Compile check
          if (doCompileCheck && compiler) {
            // Prepare shader code (add bindings if missing, but most shaders are complete)
            const shaderCode = prepareShaderCode(code);

            // Compile on the renderer's device (page, or the render worker over RPC).
            const messages = await compileOnRendererDevice(shader.id, shaderCode);
            
            // Check for errors
            const errorMessages = messages.filter(
              msg => msg.type === 'error'
            );
            
            if (errorMessages.length > 0) {
              compileError = errorMessages.map(msg => 
                `Line ${msg.lineNum}:${msg.linePos} - ${msg.message}`
              ).join('\n');
            }
          }

          // If we have onTestShader callback, run runtime test
          // The render phase below replaces this runtime test when it is enabled.
          if (onTestShader && doParamCheck && !compileError && renderMode === 'off') {
            const testValues = shader.params?.map((p: any) => {
              const min = p.min ?? 0;
              const max = p.max ?? 1;
              return min + (max - min) * 0.6; // Test at 60% of range
            }) || [];
            
            try {
              const testResult = await onTestShader(shader.id, testValues);
              if (!testResult.success) {
                paramValidation.errors.push(`Runtime test failed: ${testResult.error}`);
                paramValidation.valid = false;
              }
            } catch (e) {
              paramValidation.errors.push(`Runtime test error: ${e}`);
              paramValidation.valid = false;
            }
          }
          
          const compileTimeMs = performance.now() - startTime;
          
          // Determine final status
          const hasCompileError = !!compileError;
          const hasParamErrors = !paramValidation.valid;
          
          if (hasCompileError || hasParamErrors) {
            const errorParts: string[] = [];
            if (hasCompileError) errorParts.push(`COMPILE: ${compileError}`);
            if (hasParamErrors) errorParts.push(`PARAMS: ${paramValidation.errors.join(', ')}`);
            
            patchResult({
              status: 'error',
              errorMessage: errorParts.join(' | '),
              compileTimeMs,
              params: paramValidation.normalized,
              paramStatus: hasParamErrors ? 'invalid' : 'valid',
              paramErrors: paramValidation.errors
            });
            errors.push({
              ...shader,
              status: 'error',
              errorMessage: errorParts.join(' | '),
              compileTimeMs
            });
          } else {
            compileOk.add(shader.id);
            patchResult({
              status: 'success',
              compileTimeMs,
              params: paramValidation.normalized,
              paramStatus: paramValidation.normalized.length > 0 ? 'valid' : 'no-params'
            });
          }
        } catch (err) {
          const errorMessage = err instanceof Error ? err.message : String(err);
          patchResult({
            status: 'error',
            errorMessage,
            compileTimeMs: performance.now() - startTime,
            paramStatus: 'invalid'
          });
          errors.push({
            ...shader,
            status: 'error',
            errorMessage
          });
        }
      });

      await Promise.all(batchPromises);
      setProgress(Math.min(((i + batchSize) / targets.length) * 100, 100));
    }

    // ── Render phase: draw each passing shader, flag broken frames, save thumbnails ──
    if (renderMode !== 'off' && thumbnailHost && !abortRef.current) {
      const toRender = targets.filter((s) => compileOk.has(s.id));
      setPhase('render');
      setProgress(0);
      let restore: (() => Promise<void>) | null = null;
      let renderError: unknown = null;
      const session: CaptureSessionState = { inputSource: null };
      const pending: ThumbnailManifest = {};
      const renderFailures: Array<{ id: string; reason: string; detail: string; stats?: unknown }> = [];
      let rendered = 0;
      let saved = 0;
      const flush = async () => {
        if (!writer || Object.keys(pending).length === 0) return;
        const merged = await writer.mergeManifest({ ...pending });
        for (const k of Object.keys(pending)) delete pending[k];
        setThumbState((prev) => ({ hashes: prev?.hashes ?? null, manifest: merged }));
      };
      try {
        restore = await thumbnailHost.beginSession();
        for (const [r, shader] of toRender.entries()) {
          if (abortRef.current) break;
          updateResult(shader.id, { render: 'pending' });
          let res: CaptureResult;
          try {
            res = await captureShaderThumbnail(thumbnailHost, shader, DEFAULT_CAPTURE_OPTIONS, session);
          } catch (e) {
            res = { ok: false, reason: 'capture_failed', detail: e instanceof Error ? e.message : String(e) };
          }
          rendered++;
          if (res.ok) {
            if (renderMode === 'save' && writer) {
              await writer.writePng(shader.id, res.pngB64);
              pending[shader.id] = {
                thumbnail_url: `thumbnails/${shader.id}.png`,
                generated_at: new Date().toISOString(),
                params_snapshot: res.paramsSnapshot,
                source_hash: thumbState?.hashes?.hashes[shader.id] ?? null,
                engine: 'in-app',
              };
              saved++;
              if (saved % 10 === 0) await flush();
              updateResult(shader.id, { render: 'saved', thumb: 'fresh' });
            } else {
              updateResult(shader.id, { render: 'ok' });
            }
          } else {
            renderFailures.push({ id: shader.id, reason: res.reason, detail: res.detail, stats: 'stats' in res ? res.stats : undefined });
            updateResult(shader.id, {
              status: 'error',
              render: 'failed',
              errorMessage: `RENDER: ${res.reason} (${res.detail})`,
            });
          }
          setProgress(((r + 1) / Math.max(1, toRender.length)) * 100);
        }
      } catch (e) {
        renderError = e;
      } finally {
        // Stop, an error or a closed scanner all land here: persist what was captured and
        // give the user their slot stack back before the scan is reported finished.
        try { await flush(); } catch (e) { renderError = renderError ?? e; }
        if (restore) {
          try { await restore(); } catch (e) { renderError = renderError ?? e; }
        }
      }

      if (writer?.canWriteReports && renderMode === 'save') {
        const count = (reason: string) => renderFailures.filter((f) => f.reason === reason).length;
        await writer.writeReport('thumbnail-failures-inapp.json', {
          generated_at: new Date().toISOString(),
          engine: 'in-app',
          summary: {
            success: saved,
            failed: renderFailures.length,
            skipped: targets.length - toRender.length,
            black_frame: count('black_frame'),
            magenta_frame: count('magenta_frame'),
            error_frame: count('error_frame'),
            compile: targets.length - toRender.length,
          },
          failures: renderFailures,
        }).catch((e) => console.warn('[scanner] could not write failure report', e));
      }
      setNotice(
        `Rendered ${rendered}/${toRender.length}: ${renderMode === 'save' ? `${saved} thumbnails saved, ` : ''}` +
        `${renderFailures.length} broken frames.` +
        (saved > 0 ? ' Commit public/thumbnails, then `npm run thumbs:status`.' : '') +
        (renderError ? ` Stopped on error: ${renderError instanceof Error ? renderError.message : String(renderError)}` : ''),
      );
    }

    setPhase(null);
    setIsScanning(false);
    
    // Show summary
    const errorCount = errors.length;
    
    if (errorCount === 0) {
      console.log('✅ All shaders passed!');
    } else {
      console.error(`❌ Found ${errorCount} shaders with errors`);
      console.table(errors.map(e => ({ id: e.id, error: e.errorMessage?.slice(0, 100) })));
    }
  }, [targets, scanMode, onTestShader, renderMode, writer, thumbnailHost, thumbState, updateResult]);

  // isScanning stays true until runScan has flushed and restored, so a new scan
  // cannot start (and snapshot the thumbnail stack) while the old one unwinds.
  const stopScan = useCallback(() => {
    abortRef.current = true;
  }, []);

  const handleClose = useCallback(() => {
    abortRef.current = true;
    onClose();
  }, [onClose]);

  const exportResults = useCallback(() => {
    const errorResults = results.filter(r => r.status === 'error');
    const report = {
      timestamp: new Date().toISOString(),
      scanMode,
      totalShaders: shaders.length,
      successCount: results.filter(r => r.status === 'success').length,
      errorCount: errorResults.length,
      skippedCount: results.filter(r => r.status === 'skipped').length,
      paramStats: {
        withParams: results.filter(r => r.params && r.params.length > 0).length,
        withoutParams: results.filter(r => !r.params || r.params.length === 0).length,
        validParams: results.filter(r => r.paramStatus === 'valid').length,
        invalidParams: results.filter(r => r.paramStatus === 'invalid').length
      },
      errors: errorResults.map(r => ({
        id: r.id,
        name: r.name,
        category: r.category,
        url: r.url,
        error: r.errorMessage,
        paramStatus: r.paramStatus,
        paramErrors: r.paramErrors
      })),
      allResults: results.map(r => ({
        id: r.id,
        name: r.name,
        category: r.category,
        status: r.status,
        compileTimeMs: r.compileTimeMs,
        paramCount: r.params?.length || 0,
        paramStatus: r.paramStatus,
        params: r.params,
        thumb: r.thumb,
        render: r.render,
        lastUpgraded: r.lastUpgraded
      }))
    };

    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `shader-scan-report-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }, [results, shaders.length, scanMode]);

  const errorCount = results.filter(r => r.status === 'error').length;
  const successCount = results.filter(r => r.status === 'success').length;
  const skippedCount = results.filter(r => r.status === 'skipped').length;

  if (!isOpen) return null;

  return (
    <div style={{
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      backgroundColor: 'rgba(0, 0, 0, 0.9)',
      zIndex: 10000,
      display: 'flex',
      flexDirection: 'column',
      padding: '20px',
      fontFamily: 'monospace',
      color: '#00ff00'
    }}>
      {/* Header */}
      <div style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: '20px',
        borderBottom: '2px solid #00ff00',
        paddingBottom: '10px'
      }}>
        <h2 style={{ margin: 0 }}>🔍 Shader Compilation Scanner</h2>
        <button 
          onClick={handleClose}
          disabled={isScanning}
          style={{
            background: 'transparent',
            border: '1px solid #00ff00',
            color: '#00ff00',
            padding: '8px 16px',
            cursor: isScanning ? 'not-allowed' : 'pointer',
            opacity: isScanning ? 0.5 : 1
          }}
        >
          Close
        </button>
      </div>

      {/* WebGPU / adopted-device gate */}
      {probeFailure && <WebGpuProbeFailureOverlay probe={probeFailure} />}

      {/* Controls */}
      <div style={{ 
        display: 'flex', 
        gap: '10px', 
        marginBottom: '20px',
        alignItems: 'center',
        flexWrap: 'wrap'
      }}>
        <button
          onClick={runScan}
          disabled={isScanning || !gpuReady || (renderMode === 'save' && !writer)}
          title={renderMode === 'save' && !writer ? 'Choose the repo folder first' : undefined}
          style={{
            background: isScanning ? '#333' : '#004400',
            border: '1px solid #00ff00',
            color: '#00ff00',
            padding: '10px 20px',
            cursor: isScanning || !gpuReady || (renderMode === 'save' && !writer) ? 'not-allowed' : 'pointer',
            fontFamily: 'monospace',
            fontSize: '14px',
            opacity: isScanning || !gpuReady || (renderMode === 'save' && !writer) ? 0.5 : 1
          }}
        >
          {isScanning ? (phase === 'render' ? 'Rendering...' : 'Scanning...') : '▶️ Start Scan'}
        </button>
        
        {isScanning && (
          <button
            onClick={stopScan}
            style={{
              background: '#440000',
              border: '1px solid #ff0000',
              color: '#ff6666',
              padding: '10px 20px',
              cursor: 'pointer',
              fontFamily: 'monospace',
              fontSize: '14px'
            }}
          >
            ⏹️ Stop
          </button>
        )}

        {!isScanning && results.length > 0 && (
          <button
            onClick={exportResults}
            style={{
              background: '#000044',
              border: '1px solid #6666ff',
              color: '#6666ff',
              padding: '10px 20px',
              cursor: 'pointer',
              fontFamily: 'monospace',
              fontSize: '14px'
            }}
          >
            💾 Export Report
          </button>
        )}

        {/* Scan Mode Selector */}
        <select
          value={scanMode}
          onChange={(e) => setScanMode(e.target.value as 'compile' | 'params' | 'both')}
          disabled={isScanning}
          style={{
            background: '#001100',
            border: '1px solid #00ff00',
            color: '#00ff00',
            padding: '8px 12px',
            fontFamily: 'monospace',
            fontSize: '14px',
            cursor: isScanning ? 'not-allowed' : 'pointer'
          }}
        >
          <option value="both">🔍 Compile + Params</option>
          <option value="compile">⚙️ Compilation Only</option>
          <option value="params">🎚️ Parameters Only</option>
        </select>

        <select
          value={scope}
          onChange={(e) => setScope(e.target.value as ScanScope)}
          disabled={isScanning}
          title="Changed = thumbnail missing, or shader source changed since its thumbnail was captured"
          style={{ background: '#001100', border: '1px solid #00ff00', color: '#00ff00', padding: '8px 12px', fontFamily: 'monospace', fontSize: '14px' }}
        >
          <option value="changed">Changed since last thumbnail ({changedShaders.length})</option>
          <option value="all">All shaders ({shaders.length})</option>
        </select>

        {thumbnailHost && (
          <select
            value={renderMode}
            onChange={(e) => setRenderMode(e.target.value as ScanRenderMode)}
            disabled={isScanning}
            style={{ background: '#001100', border: '1px solid #00ff00', color: '#00ff00', padding: '8px 12px', fontFamily: 'monospace', fontSize: '14px' }}
          >
            <option value="save">🖼️ Render + save thumbnails</option>
            <option value="check">👁️ Render check only</option>
            <option value="off">No render check</option>
          </select>
        )}

        {thumbnailHost && renderMode === 'save' && (
          <button
            onClick={chooseRepoFolder}
            disabled={isScanning || !isRepoWriterSupported()}
            title={isRepoWriterSupported() ? 'Pick the image_video_effects repo folder' : 'Needs Chrome or Edge (File System Access API)'}
            style={{ background: writer ? '#002200' : '#222200', border: `1px solid ${writer ? '#00ff00' : '#ffff66'}`, color: writer ? '#00ff00' : '#ffff66', padding: '8px 12px', fontFamily: 'monospace', fontSize: '14px', cursor: 'pointer' }}
          >
            {writer ? `📁 ${writer.label}` : '📁 Choose repo folder'}
          </button>
        )}

        <div style={{ marginLeft: 'auto', display: 'flex', gap: '15px' }}>
          <span>Total: {targets.length}</span>
          <span style={{ color: '#00ff00' }}>✅ {successCount}</span>
          <span style={{ color: '#ff6666' }}>❌ {errorCount}</span>
          {skippedCount > 0 && <span style={{ color: '#ffff66' }}>⏭️ {skippedCount}</span>}
        </div>
      </div>

      {(freshSummary || notice) && (
        <div style={{ marginBottom: '12px', fontSize: '12px', color: '#88cc88' }}>
          {freshSummary && (
            <span>
              Thumbnails: {freshSummary.fresh} current · {freshSummary.stale} changed since capture · {freshSummary.missing} missing
              {freshSummary.unknown > 0 && ` · ${freshSummary.unknown} unverified (run npm run thumbs:backfill-hashes once)`}
            </span>
          )}
          {notice && <div style={{ color: '#ffff99', marginTop: '4px' }}>{notice}</div>}
        </div>
      )}

      {/* Progress Bar */}
      {isScanning && (
        <div style={{ marginBottom: '20px' }}>
          <div style={{
            width: '100%',
            height: '20px',
            background: '#111',
            border: '1px solid #00ff00'
          }}>
            <div style={{
              width: `${progress}%`,
              height: '100%',
              background: '#00ff00',
              transition: 'width 0.3s'
            }} />
          </div>
          <div style={{ textAlign: 'center', marginTop: '5px' }}>
            {phase === 'render' ? 'Rendering' : 'Compiling'} — {Math.round(progress)}%
          </div>
        </div>
      )}

      {/* Results Table */}
      <div style={{
        flex: 1,
        overflow: 'auto',
        border: '1px solid #00ff00',
        background: '#001100'
      }}>
        <table style={{
          width: '100%',
          borderCollapse: 'collapse',
          fontSize: '12px'
        }}>
          <thead style={{
            position: 'sticky',
            top: 0,
            background: '#002200'
          }}>
            <tr>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Status</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Params</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>ID</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Name</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Category</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Thumb</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Time</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Error</th>
            </tr>
          </thead>
          <tbody>
            {results.map((result, idx) => (
              <React.Fragment key={result.id}>
                <tr style={{
                  backgroundColor: idx % 2 === 0 ? 'transparent' : 'rgba(0, 255, 0, 0.05)',
                  cursor: result.params && result.params.length > 0 ? 'pointer' : 'default'
                }}
                onClick={() => result.params && result.params.length > 0 && setShowParamDetails(showParamDetails === result.id ? null : result.id)}
                >
                  <td style={{ padding: '6px 8px' }}>
                    {result.status === 'pending' && '⏳'}
                    {result.status === 'loading' && '🔄'}
                    {result.status === 'success' && '✅'}
                    {result.status === 'error' && '❌'}
                    {result.status === 'skipped' && '⏭️'}
                  </td>
                  <td style={{ padding: '6px 8px' }}>
                    {result.params && result.params.length > 0 ? (
                      <span style={{ 
                        color: result.paramStatus === 'valid' ? '#00ff00' : 
                               result.paramStatus === 'invalid' ? '#ff6666' : '#ffff00'
                      }}>
                        {result.params.length} {result.paramStatus === 'valid' ? '✓' : result.paramStatus === 'invalid' ? '✗' : '?'}
                        {result.params.length > 0 && ' ▼'}
                      </span>
                    ) : (
                      <span style={{ color: '#666' }}>-</span>
                    )}
                  </td>
                  <td style={{ padding: '6px 8px', fontFamily: 'monospace' }}>{result.id}</td>
                  <td style={{ padding: '6px 8px' }}>{result.name}</td>
                  <td style={{ padding: '6px 8px' }}>{result.category}</td>
                  <td style={{ padding: '6px 8px', whiteSpace: 'nowrap' }} title={result.lastUpgraded ? `Last upgraded ${result.lastUpgraded.slice(0, 10)}` : undefined}>
                    {result.render === 'pending' && '🔄'}
                    {result.render === 'saved' && '🖼️ saved'}
                    {result.render === 'ok' && '👁️ ok'}
                    {result.render === 'failed' && <span style={{ color: '#ff6666' }}>broken</span>}
                    {!result.render && (result.thumb ?? '-')}
                    {result.lastUpgraded && ' ⬆'}
                  </td>
                  <td style={{ padding: '6px 8px' }}>
                    {result.compileTimeMs ? `${result.compileTimeMs.toFixed(1)}ms` : '-'}
                  </td>
                  <td style={{ 
                    padding: '6px 8px', 
                    color: result.status === 'error' ? '#ff6666' : '#888',
                    maxWidth: '300px',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap'
                  }} title={result.errorMessage}>
                    {result.errorMessage || '-'}
                  </td>
                </tr>
                
                {/* Parameter Details Row */}
                {showParamDetails === result.id && result.params && result.params.length > 0 && (
                  <tr>
                    <td colSpan={8} style={{ 
                      padding: '10px 20px', 
                      background: '#001a00',
                      borderBottom: '1px solid #003300'
                    }}>
                      <div style={{ fontWeight: 'bold', marginBottom: '8px', color: '#00ff00' }}>
                        Parameter Details:
                      </div>
                      <table style={{ width: '100%', fontSize: '11px' }}>
                        <thead>
                          <tr style={{ color: '#66ff66' }}>
                            <th style={{ textAlign: 'left', padding: '4px' }}>ID</th>
                            <th style={{ textAlign: 'left', padding: '4px' }}>Name</th>
                            <th style={{ textAlign: 'left', padding: '4px' }}>Default</th>
                            <th style={{ textAlign: 'left', padding: '4px' }}>Range</th>
                            <th style={{ textAlign: 'left', padding: '4px' }}>Step</th>
                            <th style={{ textAlign: 'left', padding: '4px' }}>Mapping</th>
                          </tr>
                        </thead>
                        <tbody>
                          {result.params.map((param, pidx) => (
                            <tr key={param.id} style={{ 
                              color: param.default >= param.min && param.default <= param.max ? '#aaffaa' : '#ff6666'
                            }}>
                              <td style={{ padding: '4px', fontFamily: 'monospace' }}>{param.id}</td>
                              <td style={{ padding: '4px' }}>{param.name}</td>
                              <td style={{ padding: '4px' }}>{param.default}</td>
                              <td style={{ padding: '4px' }}>[{param.min} - {param.max}]</td>
                              <td style={{ padding: '4px' }}>{param.step || '0.01'}</td>
                              <td style={{ padding: '4px', fontFamily: 'monospace', color: '#888' }}>{param.mapping || '-'}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                      {result.paramErrors && result.paramErrors.length > 0 && (
                        <div style={{ marginTop: '8px', color: '#ff6666' }}>
                          <strong>Parameter Errors:</strong>
                          {result.paramErrors.map((err, i) => (
                            <div key={i}>• {err}</div>
                          ))}
                        </div>
                      )}
                    </td>
                  </tr>
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>
        
        {results.length === 0 && !isScanning && (
          <div style={{
            padding: '40px',
            textAlign: 'center',
            color: '#666'
          }}>
            Click "Start Scan" to check shaders for compilation errors and parameter validity
          </div>
        )}
      </div>
      
      {/* Legend */}
      <div style={{
        marginTop: '10px',
        padding: '10px',
        background: '#001100',
        border: '1px solid #003300',
        fontSize: '11px',
        color: '#888'
      }}>
        <strong>Legend:</strong>{' '}
        <span style={{ color: '#00ff00' }}>✓ Valid params</span>{' | '}
        <span style={{ color: '#ff6666' }}>✗ Invalid params</span>{' | '}
        <span style={{ color: '#ffff00' }}>? Not checked</span>{' | '}
        Click rows with params to expand details
      </div>
    </div>
  );
};

export default ShaderScanner;
