import React, { useState, useCallback, useRef } from 'react';
import { ShaderEntry } from '../renderer/types';

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
}

interface ShaderScannerProps {
  shaders: ShaderEntry[];
  isOpen: boolean;
  onClose: () => void;
  onTestShader?: (shaderId: string, testValues: number[]) => Promise<{ success: boolean; error?: string }>;
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

export const ShaderScanner: React.FC<ShaderScannerProps> = ({ shaders, isOpen, onClose, onTestShader }) => {
  const [results, setResults] = useState<ShaderScanResult[]>([]);
  const [isScanning, setIsScanning] = useState(false);
  const [scanMode, setScanMode] = useState<'compile' | 'params' | 'both'>('both');
  const [progress, setProgress] = useState(0);
  const [webgpuSupported, setWebgpuSupported] = useState<boolean | null>(null);
  const [showParamDetails, setShowParamDetails] = useState<string | null>(null);
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
    
    let device: GPUDevice | null = null;
    
    if (doCompileCheck) {
      if (!navigator.gpu) {
        alert('WebGPU is not supported in this browser');
        return;
      }

      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) {
        alert('Failed to get WebGPU adapter');
        return;
      }

      device = await adapter.requestDevice();
      if (!device) {
        alert('Failed to get WebGPU device');
        return;
      }
    }

    setIsScanning(true);
    abortRef.current = false;
    
    // Initialize results with param info if available
    const initialResults: ShaderScanResult[] = shaders.map(s => ({
      id: s.id,
      name: s.name,
      url: s.url,
      category: s.category,
      status: 'pending',
      params: s.params,
      paramStatus: s.params && s.params.length > 0 ? 'valid' : 'no-params'
    }));
    setResults(initialResults);

    const errors: ShaderScanResult[] = [];
    const batchSize = 3; // Smaller batch for more reliable testing

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
        let compileError: string | undefined;
        let paramValidation = { valid: true, errors: [] as string[], normalized: [] as ShaderParam[] };
        
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
                errorMessage: 'Not a compute shader',
                paramStatus: 'no-params'
              };
              return updated;
            });
            return;
          }

          // Validate parameters from JSON
          if (doParamCheck && shader.params) {
            paramValidation = validateParams(shader.params);
          }

          // Compile check
          if (doCompileCheck && device) {
            // Prepare shader code (add bindings if missing, but most shaders are complete)
            const shaderCode = prepareShaderCode(code);

            // Try to create the shader module
            const shaderModule = device.createShaderModule({
              label: shader.id,
              code: shaderCode
            });

            // Get compilation info
            const compilationInfo = await shaderModule.getCompilationInfo();
            
            // Check for errors
            const errorMessages = compilationInfo.messages.filter(
              msg => msg.type === 'error'
            );
            
            if (errorMessages.length > 0) {
              compileError = errorMessages.map(msg => 
                `Line ${msg.lineNum}:${msg.linePos} - ${msg.message}`
              ).join('\n');
            }
          }

          // If we have onTestShader callback, run runtime test
          if (onTestShader && doParamCheck && !compileError) {
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
            
            setResults(prev => {
              const updated = [...prev];
              updated[index] = { 
                ...updated[index], 
                status: 'error',
                errorMessage: errorParts.join(' | '),
                compileTimeMs,
                params: paramValidation.normalized,
                paramStatus: hasParamErrors ? 'invalid' : 'valid',
                paramErrors: paramValidation.errors
              };
              return updated;
            });
            errors.push({
              ...shader,
              status: 'error',
              errorMessage: errorParts.join(' | '),
              compileTimeMs
            });
          } else {
            setResults(prev => {
              const updated = [...prev];
              updated[index] = { 
                ...updated[index], 
                status: 'success',
                compileTimeMs,
                params: paramValidation.normalized,
                paramStatus: paramValidation.normalized.length > 0 ? 'valid' : 'no-params'
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
              compileTimeMs: performance.now() - startTime,
              paramStatus: 'invalid'
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
      console.log('✅ All shaders passed!');
    } else {
      console.error(`❌ Found ${errorCount} shaders with errors`);
      console.table(errors.map(e => ({ id: e.id, error: e.errorMessage?.slice(0, 100) })));
    }
  }, [shaders, scanMode, onTestShader]);

  const stopScan = useCallback(() => {
    abortRef.current = true;
    setIsScanning(false);
  }, []);

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
        params: r.params
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
        alignItems: 'center',
        flexWrap: 'wrap'
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
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Params</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>ID</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Name</th>
              <th style={{ padding: '8px', textAlign: 'left', borderBottom: '1px solid #00ff00' }}>Category</th>
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
                    <td colSpan={7} style={{ 
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
