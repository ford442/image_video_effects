/**
 * ShaderDemo - Example integration of Shadertoy import and renderer toggle
 * 
 * This demonstrates how to use:
 * - ShadertoyImporter for importing shaders
 * - RendererToggle for switching renderers
 * - RendererContext for managing renderer state
 */

import React, { useState, useCallback } from 'react';
import { ShadertoyImporter } from './ShadertoyImporter';
import { RendererToggle } from './RendererToggle';
import { useRenderer } from './RendererContext';
import { ShaderImportResult, ShaderMetadata, listShaders } from '../../services/shaderApi';

interface ShaderDemoProps {
  className?: string;
}

export const ShaderDemo: React.FC<ShaderDemoProps> = ({ className = '' }) => {
  const { currentRenderer, isWasmAvailable } = useRenderer();
  const [importedShaders, setImportedShaders] = useState<ShaderMetadata[]>([]);
  const [selectedShader, setSelectedShader] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'import' | 'library' | 'settings'>('import');

  const handleImport = useCallback((result: ShaderImportResult) => {
    setImportedShaders(prev => [result.meta, ...prev]);
    setSelectedShader(result.id);
  }, []);

  const handleLoadLibrary = useCallback(async () => {
    try {
      const shaders = await listShaders();
      setImportedShaders(shaders);
    } catch (err) {
      console.error('Failed to load shaders:', err);
    }
  }, []);

  return (
    <div style={styles.container} className={className}>
      {/* Header */}
      <div style={styles.header}>
        <h2 style={styles.title}>🎨 Shader Studio</h2>
        <div style={styles.badge}>
          {currentRenderer === 'cpp-wasm' ? '⚡ WASM' : '⚙️ JS'}
        </div>
      </div>

      {/* Tabs */}
      <div style={styles.tabs}>
        <button
          style={{ ...styles.tab, ...(activeTab === 'import' ? styles.tabActive : {}) }}
          onClick={() => setActiveTab('import')}
        >
          📥 Import
        </button>
        <button
          style={{ ...styles.tab, ...(activeTab === 'library' ? styles.tabActive : {}) }}
          onClick={() => {
            setActiveTab('library');
            handleLoadLibrary();
          }}
        >
          📚 Library
        </button>
        <button
          style={{ ...styles.tab, ...(activeTab === 'settings' ? styles.tabActive : {}) }}
          onClick={() => setActiveTab('settings')}
        >
          ⚙️ Settings
        </button>
      </div>

      {/* Content */}
      <div style={styles.content}>
        {activeTab === 'import' && (
          <div style={styles.tabContent}>
            <ShadertoyImporter
              onImport={handleImport}
              onError={(err) => console.error('Import error:', err)}
            />
            
            {importedShaders.length > 0 && (
              <div style={styles.recentImports}>
                <h4>Recent Imports</h4>
                <ul style={styles.shaderList}>
                  {importedShaders.slice(0, 5).map(shader => (
                    <li
                      key={shader.id}
                      style={{
                        ...styles.shaderItem,
                        ...(selectedShader === shader.id ? styles.shaderItemActive : {})
                      }}
                      onClick={() => setSelectedShader(shader.id)}
                    >
                      <span style={styles.shaderName}>{shader.name}</span>
                      <span style={styles.shaderSource}>{shader.source}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}

        {activeTab === 'library' && (
          <div style={styles.tabContent}>
            <h3>Your Shader Library</h3>
            {importedShaders.length === 0 ? (
              <p style={styles.emptyState}>No shaders yet. Import some from Shadertoy!</p>
            ) : (
              <ul style={styles.shaderList}>
                {importedShaders.map(shader => (
                  <li
                    key={shader.id}
                    style={{
                      ...styles.shaderItem,
                      ...(selectedShader === shader.id ? styles.shaderItemActive : {})
                    }}
                    onClick={() => setSelectedShader(shader.id)}
                  >
                    <div style={styles.shaderHeader}>
                      <span style={styles.shaderName}>{shader.name}</span>
                      {shader.tags?.includes('shadertoy') && (
                        <span style={styles.tag}>Shadertoy</span>
                      )}
                    </div>
                    <span style={styles.shaderMeta}>
                      by {shader.author} • {shader.date}
                    </span>
                    {shader.description && (
                      <p style={styles.shaderDesc}>{shader.description}</p>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}

        {activeTab === 'settings' && (
          <div style={styles.tabContent}>
            <RendererToggle showLabels />
            
            <div style={styles.settingsSection}>
              <h4>Renderer Info</h4>
              <table style={styles.infoTable}>
                <tbody>
                  <tr>
                    <td>Current Backend</td>
                    <td><code>{currentRenderer}</code></td>
                  </tr>
                  <tr>
                    <td>WASM Available</td>
                    <td>{isWasmAvailable ? '✅ Yes' : '❌ No'}</td>
                  </tr>
                  <tr>
                    <td>WebGPU Support</td>
                    <td>{'gpu' in navigator ? '✅ Yes' : '❌ No'}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div style={styles.settingsSection}>
              <h4>Build WASM Renderer</h4>
              <p style={styles.hint}>
                To enable the C++ WASM renderer, run:
              </p>
              <pre style={styles.codeBlock}>
                cd wasm_renderer && ./build.sh
              </pre>
            </div>
          </div>
        )}
      </div>

      {/* Selected Shader Preview */}
      {selectedShader && (
        <div style={styles.preview}>
          <h4>Selected Shader</h4>
          <code style={styles.shaderId}>{selectedShader}</code>
          <button
            style={styles.runButton}
            onClick={() => console.log('Load shader:', selectedShader)}
          >
            ▶ Run Shader
          </button>
        </div>
      )}
    </div>
  );
};

// --- Styles ---

const styles: Record<string, React.CSSProperties> = {
  container: {
    background: '#111827',
    borderRadius: '16px',
    overflow: 'hidden',
    maxWidth: '600px',
    color: '#f3f4f6',
    fontFamily: 'system-ui, -apple-system, sans-serif',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '20px 24px',
    borderBottom: '1px solid #374151',
  },
  title: {
    margin: 0,
    fontSize: '20px',
    fontWeight: 700,
  },
  badge: {
    padding: '6px 12px',
    background: '#374151',
    borderRadius: '20px',
    fontSize: '12px',
    fontWeight: 600,
  },
  tabs: {
    display: 'flex',
    borderBottom: '1px solid #374151',
  },
  tab: {
    flex: 1,
    padding: '14px',
    background: 'transparent',
    border: 'none',
    color: '#9ca3af',
    fontSize: '14px',
    cursor: 'pointer',
    transition: 'all 0.2s',
  },
  tabActive: {
    color: '#f3f4f6',
    background: '#1f2937',
    borderBottom: '2px solid #6366f1',
  },
  content: {
    padding: '20px',
  },
  tabContent: {
    animation: 'fadeIn 0.2s ease',
  },
  recentImports: {
    marginTop: '20px',
    paddingTop: '20px',
    borderTop: '1px solid #374151',
  },
  shaderList: {
    listStyle: 'none',
    padding: 0,
    margin: '12px 0 0 0',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '8px',
  },
  shaderItem: {
    padding: '12px',
    background: '#1f2937',
    borderRadius: '8px',
    cursor: 'pointer',
    transition: 'all 0.2s',
    border: '1px solid transparent',
  },
  shaderItemActive: {
    borderColor: '#6366f1',
    background: '#252f47',
  },
  shaderHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    marginBottom: '4px',
  },
  shaderName: {
    fontWeight: 600,
    color: '#f3f4f6',
  },
  shaderSource: {
    fontSize: '11px',
    color: '#6b7280',
  },
  shaderMeta: {
    fontSize: '12px',
    color: '#6b7280',
  },
  shaderDesc: {
    fontSize: '12px',
    color: '#9ca3af',
    margin: '8px 0 0 0',
    lineHeight: 1.5,
  },
  tag: {
    padding: '2px 8px',
    background: '#6366f1',
    borderRadius: '4px',
    fontSize: '10px',
    fontWeight: 600,
    color: 'white',
  },
  emptyState: {
    textAlign: 'center' as const,
    color: '#6b7280',
    padding: '40px 20px',
  },
  settingsSection: {
    marginTop: '20px',
    paddingTop: '20px',
    borderTop: '1px solid #374151',
  },
  infoTable: {
    width: '100%',
    fontSize: '13px',
    borderCollapse: 'collapse' as const,
  },
  infoTableTd: {
    padding: '8px 0',
    borderBottom: '1px solid #374151',
  },
  hint: {
    fontSize: '13px',
    color: '#9ca3af',
  },
  codeBlock: {
    background: '#000',
    padding: '12px',
    borderRadius: '8px',
    fontSize: '12px',
    overflow: 'auto',
    color: '#4ade80',
    fontFamily: 'monospace',
  },
  preview: {
    padding: '16px 20px',
    background: '#0f172a',
    borderTop: '1px solid #374151',
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  },
  shaderId: {
    fontSize: '12px',
    color: '#6b7280',
    background: '#1f2937',
    padding: '4px 8px',
    borderRadius: '4px',
  },
  runButton: {
    marginLeft: 'auto',
    padding: '8px 16px',
    background: '#10b981',
    border: 'none',
    borderRadius: '6px',
    color: 'white',
    fontSize: '13px',
    fontWeight: 600,
    cursor: 'pointer',
  },
};

// Add keyframes
const styleSheet = document.createElement('style');
styleSheet.textContent = `
  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(-10px); }
    to { opacity: 1; transform: translateY(0); }
  }
`;
document.head.appendChild(styleSheet);

export default ShaderDemo;
