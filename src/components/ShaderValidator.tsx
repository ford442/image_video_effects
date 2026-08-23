import React, { useRef, useState } from 'react';
import { INTERNAL_RENDER_RESOLUTION } from '../config/appConfig';
import {
  publishWebGpuProbe,
  runWebGpuBootProbe,
  toWebGpuProbeBreadcrumb,
  type WebGpuProbeSerializable,
} from '../renderer/webgpuBootProbe';
import { getAdoptedRendererDevice, registerAdoptedRendererDevice } from '../utils/adoptedGpuDevice';
import { resolveShaderUrl } from '../utils/resolveShaderUrl';
import { WebGpuProbeFailureOverlay } from './WebGpuProbeFailureOverlay';

interface ShaderDef {
  id: string;
  name: string;
  url: string;
}

interface ValidationResult {
  id: string;
  name: string;
  url: string;
  status: 'pass' | 'fail' | 'warning' | 'missing';
  error?: string;
  durationMs?: number;
}

const SHADER_LIST_FILES = [
  'image.json', 'generative.json', 'interactive-mouse.json',
  'distortion.json', 'simulation.json', 'liquid-effects.json',
  'artistic.json', 'geometric.json', 'hybrid.json', 'advanced-hybrid.json',
  'visual-effects.json', 'lighting-effects.json', 'retro-glitch.json', 'post-processing.json'
];

async function ensureAdoptedDevice(
  canvas: HTMLCanvasElement | null,
): Promise<{ device: GPUDevice } | { failure: WebGpuProbeSerializable }> {
  const existing = getAdoptedRendererDevice();
  if (existing) {
    return { device: existing };
  }

  if (window.webgpuProbe?.ok === true) {
    return {
      failure: {
        ...window.webgpuProbe,
        ok: false,
        lastError: 'Boot probe succeeded but no adopted GPUDevice is registered',
        failedStage: 'requestDevice',
      },
    };
  }

  if (!canvas) {
    return {
      failure: {
        ok: false,
        finishedAt: new Date().toISOString(),
        userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
        userAgentBrands: [],
        attempts: [],
        lastError: 'Hidden canvas unavailable for WebGPU boot probe',
        failedStage: 'getContext',
      },
    };
  }

  canvas.width = INTERNAL_RENDER_RESOLUTION;
  canvas.height = INTERNAL_RENDER_RESOLUTION;
  const probe = await runWebGpuBootProbe(canvas, INTERNAL_RENDER_RESOLUTION, INTERNAL_RENDER_RESOLUTION);
  publishWebGpuProbe(probe);

  if (!probe.ok || !probe.handoff?.device) {
    return { failure: toWebGpuProbeBreadcrumb(probe) };
  }

  registerAdoptedRendererDevice(probe.handoff.device, probe.handoff.supportsSubgroups);
  return { device: probe.handoff.device };
}

export const ShaderValidator: React.FC = () => {
  const probeCanvasRef = useRef<HTMLCanvasElement>(null);
  const [results, setResults] = useState<ValidationResult[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [currentTest, setCurrentTest] = useState('');
  const [progress, setProgress] = useState({ current: 0, total: 0 });
  const [showOnlyFailures, setShowOnlyFailures] = useState(true);
  const [probeFailure, setProbeFailure] = useState<WebGpuProbeSerializable | null>(null);

  const collectAllShaders = async (): Promise<ShaderDef[]> => {
    const allShaders: ShaderDef[] = [];
    const seen = new Set<string>();

    for (const listFile of SHADER_LIST_FILES) {
      try {
        const res = await fetch(`/shader-lists/${listFile}`);
        if (!res.ok) continue;

        const list: any[] = await res.json();

        for (const entry of list) {
          if (!entry.url || seen.has(entry.id)) continue;
          seen.add(entry.id);

          const url = resolveShaderUrl(entry.url);

          allShaders.push({
            id: entry.id,
            name: entry.name || entry.id,
            url,
          });
        }
      } catch (e) {
        console.warn(`Could not load ${listFile}`);
      }
    }
    return allShaders;
  };

  const validateShader = async (def: ShaderDef, device: GPUDevice): Promise<ValidationResult> => {
    const start = performance.now();

    try {
      const wgslRes = await fetch(resolveShaderUrl(def.url));

      if (wgslRes.status === 404) {
        return {
          ...def,
          status: 'missing',
          error: 'File not found (404)',
          durationMs: Math.round(performance.now() - start),
        };
      }

      if (!wgslRes.ok) {
        return {
          ...def,
          status: 'fail',
          error: `HTTP ${wgslRes.status}`,
          durationMs: Math.round(performance.now() - start),
        };
      }

      const wgslCode = await wgslRes.text();

      if (!wgslCode.trim()) {
        return { ...def, status: 'fail', error: 'Empty file', durationMs: Math.round(performance.now() - start) };
      }

      const shaderModule = device.createShaderModule({ code: wgslCode });
      const info = await shaderModule.getCompilationInfo();

      const errors = info.messages.filter(m => m.type === 'error');

      if (errors.length > 0) {
        return {
          ...def,
          status: 'fail',
          error: errors.map(e => `L${e.lineNum}:${e.linePos} — ${e.message}`).join('\n'),
          durationMs: Math.round(performance.now() - start),
        };
      }

      return {
        ...def,
        status: 'pass',
        durationMs: Math.round(performance.now() - start),
      };
    } catch (err: any) {
      return {
        ...def,
        status: 'fail',
        error: err.message || String(err),
        durationMs: Math.round(performance.now() - start),
      };
    }
  };

  const runValidation = async () => {
    setProbeFailure(null);
    const adopted = await ensureAdoptedDevice(probeCanvasRef.current);
    if ('failure' in adopted) {
      setProbeFailure(adopted.failure);
      return;
    }

    setIsRunning(true);
    setResults([]);
    setProgress({ current: 0, total: 0 });

    const shaders = await collectAllShaders();
    setProgress({ current: 0, total: shaders.length });

    const newResults: ValidationResult[] = [];

    for (let i = 0; i < shaders.length; i++) {
      const shader = shaders[i];
      setCurrentTest(`${shader.name} (${shader.id})`);
      setProgress({ current: i + 1, total: shaders.length });

      const result = await validateShader(shader, adopted.device);
      newResults.push(result);
      setResults([...newResults]);

      await new Promise(r => setTimeout(r, 20));
    }

    setCurrentTest('');
    setIsRunning(false);
  };

  const exportReport = () => {
    const report = {
      timestamp: new Date().toISOString(),
      total: results.length,
      passed: results.filter(r => r.status === 'pass').length,
      failed: results.filter(r => r.status === 'fail').length,
      missing: results.filter(r => r.status === 'missing').length,
      failures: results.filter(r => r.status !== 'pass'),
    };

    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `shader-validation-${new Date().toISOString().slice(0,10)}.json`;
    a.click();
  };

  const displayedResults = showOnlyFailures
    ? results.filter(r => r.status !== 'pass')
    : results;

  const missingCount = results.filter(r => r.status === 'missing').length;
  const errorCount = results.filter(r => r.status === 'fail').length;
  const passCount = results.filter(r => r.status === 'pass').length;

  return (
    <div style={{ padding: 20, fontFamily: 'monospace', background: '#111', color: '#0f0' }}>
      <canvas ref={probeCanvasRef} width={1} height={1} style={{ display: 'none' }} aria-hidden />
      <h1>Shader Validator</h1>

      {probeFailure && <WebGpuProbeFailureOverlay probe={probeFailure} />}

      <button
        onClick={runValidation}
        disabled={isRunning}
        style={{ padding: '10px 20px', fontSize: 16 }}
      >
        {isRunning ? 'Validating...' : 'Run Full Validation'}
      </button>

      {results.length > 0 && (
        <button onClick={exportReport} style={{ marginLeft: 12, padding: '10px 16px' }}>
          Export Report
        </button>
      )}

      <label style={{ marginLeft: 20 }}>
        <input type="checkbox" checked={showOnlyFailures} onChange={e => setShowOnlyFailures(e.target.checked)} />
        Show only problems
      </label>

      {isRunning && (
        <div style={{ margin: '16px 0' }}>
          <div>Testing {progress.current} / {progress.total}: <strong>{currentTest}</strong></div>
          <progress value={progress.current} max={progress.total} style={{ width: '100%' }} />
        </div>
      )}

      {results.length > 0 && (
        <div style={{ margin: '16px 0', fontSize: 15 }}>
          <strong>Summary:</strong> ✅ {passCount} passed &nbsp;&nbsp;
          ❌ {errorCount} errors &nbsp;&nbsp;
          📁 {missingCount} missing files
        </div>
      )}

      <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 10 }}>
        <thead>
          <tr style={{ background: '#222' }}>
            <th style={{ padding: 8, textAlign: 'left' }}>Status</th>
            <th style={{ padding: 8, textAlign: 'left' }}>Shader</th>
            <th style={{ padding: 8, textAlign: 'left' }}>Details</th>
            <th style={{ padding: 8 }}>Time</th>
          </tr>
        </thead>
        <tbody>
          {displayedResults.map((r, i) => (
            <tr key={i} style={{
              background: r.status === 'fail' ? '#300' : r.status === 'missing' ? '#330' : 'transparent',
              borderBottom: '1px solid #333'
            }}>
              <td style={{ padding: 8, fontWeight: 'bold' }}>
                {r.status === 'pass' ? '✅' : r.status === 'missing' ? '📁' : '❌'}
              </td>
              <td style={{ padding: 8 }}>
                {r.name}<br />
                <span style={{ fontSize: 11, opacity: 0.6 }}>{r.id}</span>
              </td>
              <td style={{ padding: 8, whiteSpace: 'pre-wrap', fontSize: 12 }}>
                {r.error || 'OK'}
              </td>
              <td style={{ padding: 8, textAlign: 'right', fontSize: 12 }}>{r.durationMs}ms</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

export default ShaderValidator;
