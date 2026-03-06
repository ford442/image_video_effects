import React, { useState } from 'react';
import { importFromShadertoy } from '../../services/shaderApi';

interface ShadertoyImporterProps {
  onImported?: (id: string) => void;
  className?: string;
}

export const ShadertoyImporter: React.FC<ShadertoyImporterProps> = ({ onImported, className = '' }) => {
  const [shaderId, setShaderId] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [status, setStatus] = useState('');

  const handleImport = async () => {
    setStatus('Importing from Shadertoy...');
    const result = await importFromShadertoy(shaderId, apiKey);
    if (result.success) {
      setStatus(`✅ Imported ${result.name}`);
      onImported?.(result.id);
    } else setStatus('❌ Failed – check ID/key');
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
