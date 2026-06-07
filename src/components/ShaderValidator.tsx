import React, { useState } from 'react';
import { resolveShaderUrl } from '../utils/resolveShaderUrl';

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
  'image.json', 'generative.json', 'interactive.json', 'interactive-mouse.json',
  'distortion.json', 'simulation.json', 'liquid.json', 'liquid-effects.json',
  'artistic.json', 'geometric.json', 'hybrid.json', 'advanced-hybrid.json',
  'visual-effects.json', 'lighting-effects.json', 'retro-glitch.json', 'post-processing.json'
];

export const ShaderValidator: React.FC = () => {
  const [results, setResults] = useState<ValidationResult[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [currentTest, setCurrentTest] = useState('');
  const [progress, setProgress] = useState({ current: 0, total: 0 });
  const [showOnlyFailures, setShowOnlyFailures] = useState(true);

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

          // Resolve shader URL against the configured base URL.
          // Absolute URLs are left intact; relative ones are resolved.
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

  const validateShader = async (def: ShaderDef): Promise<ValidationResult> => {
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

      const adapter = await navigator.gpu?.requestAdapter();
      if (!adapter) throw new Error('No WebGPU adapter');

      const device = await adapter.requestDevice();
      const shaderModule = device.createShaderModule({ code: wgslCode });
      const info = await shaderModule.getCompilationInfo();

      const errors = info.messages.filter(m => m.type === 'error');

      if (errors.length > 0) {
        device.destroy();
        return {
          ...def,
          status: 'fail',
          error: errors.map(e => `L${e.lineNum}:${e.linePos} — ${e.message}`).join('\n'),
          durationMs: Math.round(performance.now() - start),
        };
      }

      device.destroy();

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

      const result = await validateShader(shader);
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
      <h1>Shader Validator</h1>

      <button onClick={runValidation} disabled={isRunning} style={{ padding: '10px 20px', fontSize: 16 }}>
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
