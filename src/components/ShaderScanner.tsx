import React, { useState, useCallback, useRef } from 'react';
import { ShaderEntry } from '../renderer/types';

interface ShaderScanResult {
  id: string;
  name: string;
  url: string;
  category: string;
  status: 'pending' | 'loading' | 'success' | 'error' | 'skipped';
  errorMessage?: string;
  compileTimeMs?: number;
}

interface ShaderScannerProps {
  shaders: ShaderEntry[];
  isOpen: boolean;
  onClose: () => void;
}

// Simple template wrapper to make shaders compile-testable
const WRAPPER_TEMPLATE = `
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

__SHADER_CODE__
`;

export const ShaderScanner: React.FC<ShaderScannerProps> = ({ shaders, isOpen, onClose }) => {
  const [results, setResults] = useState<ShaderScanResult[]>([]);
  const [isScanning, setIsScanning] = useState(false);
  const [progress, setProgress] = useState(0);
  const [webgpuSupported, setWebgpuSupported] = useState<boolean | null>(null);
  const abortRef = useRef(false);

  // Check WebGPU support once when opened
  React.useEffect(() => {
    if (isOpen && webgpuSupported === null) {
      const checkSupport = async () => {
        if (!navigator.gpu) {
          setWebgpuSupported(false);
          return;
        }
        try {
          const adapter = await navigator.gpu.requestAdapter();
          setWebgpuSupported(!!adapter);
        } catch {
          setWebgpuSupported(false);
        }
      };
      checkSupport();
    }
  }, [isOpen, webgpuSupported]);

  const runScan = useCallback(async () => {
    if (!navigator.gpu) {
      alert('WebGPU is not supported in this browser');
      return;
    }

    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) {
      alert('Failed to get WebGPU adapter');
      return;
    }

    const device = await adapter.requestDevice();
    if (!device) {
      alert('Failed to get WebGPU device');
      return;
    }

    setIsScanning(true);
    abortRef.current = false;
    
    // Initialize results
    const initialResults: ShaderScanResult[] = shaders.map(s => ({
      id: s.id,
      name: s.name,
      url: s.url,
      category: s.category,
      status: 'pending'
    }));
    setResults(initialResults);

    const errors: ShaderScanResult[] = [];
    const batchSize = 5; // Process in batches to avoid overwhelming the GPU

    for (let i = 0; i < shaders.length; i += batchSize) {
      if (abortRef.current) break;

      const batch = shaders.slice(i, i + batchSize);
      const batchPromises = batch.map(async (shader, batchIndex) => {
        const index = i + batchIndex;
        
        // Update status to loading
        setResults(prev => {
          const updated = [...prev];
          updated[index] = { ...updated[index], status: 'loading' };
          return updated;
        });

        const startTime = performance.now();
        
        try {
          // Fetch the shader code
          const response = await fetch(shader.url);
          if (!response.ok) {
            throw new Error(`Failed to fetch: ${response.status} ${response.statusText}`);
          }
          
          const code = await response.text();
          
          // Skip if not a compute shader
          if (!code.includes('@compute')) {
            setResults(prev => {
              const updated = [...prev];
              updated[index] = { 
                ...updated[index], 
                status: 'skipped',
                errorMessage: 'Not a compute shader'
              };
              return updated;
            });
            return;
          }

          // Wrap the shader with required bindings
          const wrappedCode = WRAPPER_TEMPLATE.replace('__SHADER_CODE__', code);

          // Try to create the shader module
          const shaderModule = device.createShaderModule({
            label: shader.id,
            code: wrappedCode
          });

          // Get compilation info
          const compilationInfo = await shaderModule.getCompilationInfo();
          
          const compileTimeMs = performance.now() - startTime;
          
          // Check for errors
          const errorMessages = compilationInfo.messages.filter(
            msg => msg.type === 'error'
          );
          
          if (errorMessages.length > 0) {
            const errorText = errorMessages.map(msg => 
              `Line ${msg.lineNum}:${msg.linePos} - ${msg.message}`
            ).join('\n');
            
            setResults(prev => {
              const updated = [...prev];
              updated[index] = { 
                ...updated[index], 
                status: 'error',
                errorMessage: errorText,
                compileTimeMs
              };
              return updated;
            });
            errors.push({
              ...shader,
              status: 'error',
              errorMessage: errorText,
              compileTimeMs
            });
          } else {
            setResults(prev => {
              const updated = [...prev];
              updated[index] = { 
                ...updated[index], 
                status: 'success',
                compileTimeMs
              };
              return updated;
            });
          }
        } catch (err) {
          const errorMessage = err instanceof Error ? err.message : String(err);
          setResults(prev => {
            const updated = [...prev];
            updated[index] = { 
              ...updated[index], 
              status: 'error',
              errorMessage,
              compileTimeMs: performance.now() - startTime
            };
            return updated;
          });
          errors.push({
            ...shader,
            status: 'error',
            errorMessage
          });
        }
      });

      await Promise.all(batchPromises);
      setProgress(Math.min(((i + batchSize) / shaders.length) * 100, 100));
    }

    setIsScanning(false);
    
    // Show summary
    const errorCount = errors.length;
    
    if (errorCount === 0) {
      console.log('✅ All shaders compiled successfully!');
    } else {
      console.error(`❌ Found ${errorCount} shaders with compilation errors`);
      console.table(errors.map(e => ({ id: e.id, error: e.errorMessage?.slice(0, 100) })));
    }
  }, [shaders, results]);

  const stopScan = useCallback(() => {
    abortRef.current = true;
    setIsScanning(false);
  }, []);

  const exportResults = useCallback(() => {
    const errorResults = results.filter(r => r.status === 'error');
    const report = {
      timestamp: new Date().toISOString(),
      totalShaders: shaders.length,
      successCount: results.filter(r => r.status === 'success').length,
      errorCount: errorResults.length,
      skippedCount: results.filter(r => r.status === 'skipped').length,
      errors: errorResults.map(r => ({
        id: r.id,
        name: r.name,
        category: r.category,
        url: r.url,
        error: r.errorMessage
      }))
    };

    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `shader-scan-report-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }, [results, shaders.length]);

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
          onClick={onClose}
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

      {/* WebGPU Status */}
      {webgpuSupported === false && (
        <div style={{ 
          background: '#330000', 
          border: '1px solid #ff0000', 
          padding: '15px', 
          marginBottom: '20px',
          color: '#ff6666'
        }}>
          ⚠️ WebGPU is not supported in this browser. Shader compilation scanning requires WebGPU.
        </div>
      )}

      {/* Controls */}
      <div style={{ 
        display: 'flex', 
        gap: '10px', 
        marginBottom: '20px',
        alignItems: 'center'
      }}>
        <button
          onClick={runScan}
          disabled={isScanning || webgpuSupported === false}
          style={{
            background: isScanning ? '#333' : '#004400',
            border: '1px solid #00ff00',
            color: '#00ff00',
            padding: '10px 20px',
            cursor: isScanning || webgpuSupported === false ? 'not-allowed' : 'pointer',
            fontFamily: 'monospace',
            fontSize: '14px',
            opacity: isScanning || webgpuSupported === false ? 0.5 : 1
          }}
        >
          {isScanning ? 'Scanning...' : '▶️ Start Scan'}
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

        <div style={{ marginLeft: 'auto', display: 'flex', gap: '15px' }}>
          <span>Total: {shaders.length}</span>
          <span style={{ color: '#00ff00' }}>✅ {successCount}</span>
          <span style={{ color: '#ff6666' }}>❌ {errorCount}</span>
          {skippedCount > 0 && <span style={{ color: '#ffff66' }}>⏭️ {skippedCount}</span>}
        </div>
      </div>

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
            {Math.round(progress)}% ({Math.floor(progress * shaders.length / 100)} / {shaders.length})
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
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>ID</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Name</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Category</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Time</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Error</th>
            </tr>
          </thead>
          <tbody>
            {results.map((result, idx) => (
              <tr key={result.id} style={{
                backgroundColor: idx % 2 === 0 ? 'transparent' : 'rgba(0, 255, 0, 0.05)'
              }}>
                <td style={{ padding: '6px 8px' }}>
                  {result.status === 'pending' && '⏳'}
                  {result.status === 'loading' && '🔄'}
                  {result.status === 'success' && '✅'}
                  {result.status === 'error' && '❌'}
                  {result.status === 'skipped' && '⏭️'}
                </td>
                <td style={{ padding: '6px 8px', fontFamily: 'monospace' }}>{result.id}</td>
                <td style={{ padding: '6px 8px' }}>{result.name}</td>
                <td style={{ padding: '6px 8px' }}>{result.category}</td>
                <td style={{ padding: '6px 8px' }}>
                  {result.compileTimeMs ? `${result.compileTimeMs.toFixed(1)}ms` : '-'}
                </td>
                <td style={{ 
                  padding: '6px 8px', 
                  color: result.status === 'error' ? '#ff6666' : '#888',
                  maxWidth: '400px',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap'
                }} title={result.errorMessage}>
                  {result.errorMessage || '-'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        
        {results.length === 0 && !isScanning && (
          <div style={{
            padding: '40px',
            textAlign: 'center',
            color: '#666'
          }}>
            Click "Start Scan" to begin checking shaders for compilation errors
          </div>
        )}
      </div>
    </div>
  );
};

export default ShaderScanner;
