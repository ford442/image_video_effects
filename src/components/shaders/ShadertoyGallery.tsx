import React, { useState } from 'react';
import { importFromShadertoy } from '../../services/shaderApi';

interface ShaderResult {
  id: string;
  name: string;
  username: string;
  description?: string;
}

interface ShadertoyGalleryProps {
  onImported?: (id: string) => void;
  apiKey?: string;
  className?: string;
}

export const ShadertoyGallery: React.FC<ShadertoyGalleryProps> = ({ 
  onImported, 
  apiKey: defaultApiKey = '',
  className = '' 
}) => {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<ShaderResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [apiKey, setApiKey] = useState(defaultApiKey);
  const [importingId, setImportingId] = useState<string | null>(null);

  const search = async () => {
    if (!query.trim() || !apiKey.trim()) return;
    
    setLoading(true);
    try {
      const res = await fetch(
        `https://www.shadertoy.com/api/shaders/query/${encodeURIComponent(query)}?key=${apiKey}`
      );
      const data = await res.json();
      setResults(data.Results || []);
    } catch (err) {
      console.error('Search failed:', err);
    }
    setLoading(false);
  };

  const handleImport = async (shaderId: string) => {
    if (!apiKey.trim()) {
      const key = prompt('Enter your Shadertoy API Key:');
      if (!key) return;
      setApiKey(key);
    }
    
    setImportingId(shaderId);
    try {
      const result = await importFromShadertoy(shaderId, apiKey);
      if (result.success) {
        onImported?.(result.id);
      }
    } catch (err) {
      console.error('Import failed:', err);
    }
    setImportingId(null);
  };

  return (
    <div className={`p-6 ${className}`}>
      <div className="flex gap-3 mb-6">
        <input 
          placeholder="Search Shadertoy (nebula, fluid, fractal...)" 
          value={query} 
          onChange={e => setQuery(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && search()}
          className="flex-1 p-4 bg-[#16213e] rounded-2xl text-lg text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-[#e94560]"
        />
        <input
          type="password"
          placeholder="API Key"
          value={apiKey}
          onChange={e => setApiKey(e.target.value)}
          className="w-48 p-4 bg-[#16213e] rounded-2xl text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-[#e94560]"
        />
        <button 
          onClick={search}
          disabled={loading || !query.trim()}
          className="px-6 bg-[#e94560] hover:bg-[#ff6b6b] disabled:opacity-50 rounded-2xl font-bold transition-colors"
        >
          {loading ? '...' : '🔍'}
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {results.map(s => (
          <div key={s.id} className="bg-[#16213e] rounded-2xl overflow-hidden group hover:ring-2 hover:ring-[#e94560] transition-all">
            <div className="relative">
              <img 
                src={`https://www.shadertoy.com/img/${s.id}.jpg`} 
                alt={s.name}
                className="w-full h-48 object-cover"
                onError={(e) => {
                  (e.target as HTMLImageElement).src = 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200" fill="%2316213e"/>';
                }}
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/80 to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
            </div>
            <div className="p-4">
              <h4 className="font-bold text-white truncate">{s.name}</h4>
              <p className="text-sm text-white/60">by {s.username}</p>
              <button 
                onClick={() => handleImport(s.id)}
                disabled={importingId === s.id}
                className="mt-4 w-full bg-[#e94560] hover:bg-[#ff6b6b] disabled:opacity-50 py-2 rounded-xl font-bold transition-colors"
              >
                {importingId === s.id ? '⏳ Importing...' : 'Import to Pixelocity'}
              </button>
            </div>
          </div>
        ))}
      </div>

      {!loading && results.length === 0 && query && (
        <div className="text-center text-white/50 py-12">
          No results found. Try a different search term.
        </div>
      )}
    </div>
  );
};

export default ShadertoyGallery;
