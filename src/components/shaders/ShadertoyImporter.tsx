import React, { useState } from 'react';
import { importFromShadertoy, ShaderImportResult } from '../../services/shaderApi';

interface ShadertoyImporterProps {
  /** Called with full import result when import succeeds */
  onImport?: (result: ShaderImportResult) => void;
  /** Deprecated: Use onImport instead. Called with just the shader ID. */
  onImported?: (id: string) => void;
  /** Called when import fails */
  onError?: (error: Error) => void;
  className?: string;
}

export const ShadertoyImporter: React.FC<ShadertoyImporterProps> = ({
  onImport,
  onImported,
  onError,
  className = ''
}) => {
  const [shaderId, setShaderId] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [status, setStatus] = useState('');

  const handleImport = async () => {
    setStatus('Importing from Shadertoy...');
    try {
      const result = await importFromShadertoy(shaderId, apiKey);
      if (result.success) {
        setStatus(`✅ Imported ${result.name}`);
        onImport?.(result);
        onImported?.(result.id); // Backward compatibility
      } else {
        setStatus('❌ Failed – check ID/key');
      }
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      setStatus(`❌ Error: ${error.message}`);
      onError?.(error);
    }
  };

  return (
    <div className={`p-6 bg-[#16213e] rounded-2xl ${className}`}>
      <input 
        placeholder="Shadertoy ID (e.g. 4dXGRn)" 
        value={shaderId} 
        onChange={e => setShaderId(e.target.value)} 
        className="w-full mb-3 p-3 bg-black/50 rounded text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-[#e94560]" 
      />
      <input 
        type="password" 
        placeholder="Your Shadertoy API Key" 
        value={apiKey} 
        onChange={e => setApiKey(e.target.value)} 
        className="w-full mb-3 p-3 bg-black/50 rounded text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-[#e94560]" 
      />
      <button 
        onClick={handleImport} 
        className="w-full bg-[#e94560] hover:bg-[#ff6b6b] transition-colors py-3 rounded-xl font-bold"
      >
        Import & Store
      </button>
      <div className="text-xs text-white/70 mt-3">{status}</div>
    </div>
  );
};

export default ShadertoyImporter;
