import React, { useState, useEffect } from 'react';
import { shaderApi, ShaderMeta, CategoryGroup } from '../services/shaderApi';
import './ShaderBrowser.css';

// Category hierarchy for UI organization
const CATEGORY_GROUPS: Record<string, CategoryGroup> = {
  interactive: {
    label: '🖱️ Interactive',
    description: 'Mouse and touch-driven effects',
    subcategories: ['interactive']
  },
  generative: {
    label: '✨ Generative',
    description: 'Procedural and algorithmic art',
    subcategories: ['generative', 'simulation']
  },
  distortion: {
    label: '🔮 Distortion',
    description: 'Warp, bend, and transform space',
    subcategories: ['distortion', 'warp']
  },
  image: {
    label: '🖼️ Image',
    description: 'Filters, color grading, and adjustments',
    subcategories: ['image', 'filter']
  },
  artistic: {
    label: '🎨 Artistic',
    description: 'Stylized looks and painterly effects',
    subcategories: ['artistic']
  },
  retro: {
    label: '📺 Retro & Glitch',
    description: 'Vintage, analog, and digital corruption',
    subcategories: ['retro-glitch', 'glitch']
  },
  geometric: {
    label: '📐 Geometric',
    description: 'Patterns, tessellation, and shapes',
    subcategories: ['geometric', 'tessellation', 'geometry']
  },
  visual: {
    label: '🎬 Visual Effects',
    description: 'Particles, glow, overlays, and VFX',
    subcategories: ['visual-effects', 'lighting']
  },
  liquid: {
    label: '💧 Liquid',
    description: 'Fluid, water, oil, and viscous effects',
    subcategories: ['liquid']
  },
  other: {
    label: '🔧 Other',
    description: 'Miscellaneous and specialized effects',
    subcategories: ['transition', 'feedback', 'shader', 'reactive']
  }
};

export const ShaderBrowser: React.FC<{
  onSelect: (shader: ShaderMeta, code: string) => void;
  selectedId?: string;
}> = ({ onSelect, selectedId }) => {
  const [shaders, setShaders] = useState<ShaderMeta[]>([]);
  const [filter, setFilter] = useState('');
  const [category, setCategory] = useState('');
  const [loading, setLoading] = useState(true);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editDesc, setEditDesc] = useState('');
  const [editTags, setEditTags] = useState('');
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null);

  useEffect(() => {
    loadShaders();
  }, [category]);

  const loadShaders = async () => {
    setLoading(true);
    try {
      const data = await shaderApi.list({ 
        category, 
        sortBy: 'rating',
        minStars: 0 
      });
      setShaders(data);
    } catch (err) {
      console.error('Failed to load shaders:', err);
    }
    setLoading(false);
  };

  const handleRate = async (shaderId: string, stars: number, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      const updated = await shaderApi.rate(shaderId, stars);
      setShaders(prev => prev.map(s => s.id === shaderId ? updated : s));
    } catch (err) {
      console.error('Rating failed:', err);
    }
  };

  const startEdit = (shader: ShaderMeta) => {
    setEditingId(shader.id);
    setEditDesc(shader.description);
    setEditTags(shader.tags.join(', '));
  };

  const saveEdit = async (shaderId: string) => {
    try {
      const updated = await shaderApi.update(shaderId, { 
        description: editDesc, 
        tags: editTags.split(',').map(t => t.trim()).filter(Boolean)
      });
      setShaders(prev => prev.map(s => s.id === shaderId ? updated : s));
      setEditingId(null);
    } catch (err) {
      console.error('Update failed:', err);
    }
  };

  const handleSelect = async (shader: ShaderMeta) => {
    try {
      const { code } = await shaderApi.getCode(shader.id);
      onSelect(shader, code);
    } catch (err) {
      console.error('Failed to load shader code:', err);
    }
  };

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files?.[0]) return;
    const file = e.target.files[0];
    const name = prompt('Shader name:') || file.name.replace('.wgsl', '');
    const desc = prompt('Description:') || '';
    const tags = prompt('Tags (comma-separated):') || '';
    try {
      await shaderApi.upload(file, { 
        name, 
        description: desc, 
        tags: tags.split(',').map(t => t.trim()).filter(Boolean)
      });
      loadShaders();
    } catch (err) {
      alert('Upload failed: ' + err);
    }
  };

  const filteredShaders = shaders.filter(s => 
    s.name.toLowerCase().includes(filter.toLowerCase()) ||
    s.description.toLowerCase().includes(filter.toLowerCase()) ||
    s.tags.some(t => t.toLowerCase().includes(filter.toLowerCase()))
  );

  return (
    <div className="shader-browser">
      <div className="shader-filters">
        <input 
          type="text" 
          placeholder="Search shaders..." 
          value={filter}
          onChange={e => setFilter(e.target.value)}
          className="shader-search"
        />
        <select 
          value={category} 
          onChange={e => setCategory(e.target.value)}
          className="shader-category"
          title={category ? CATEGORY_GROUPS[category]?.description || 'Select a category' : 'All shader categories'}
        >
          <option value="">All Categories ({shaders.length} shaders)</option>
          {Object.entries(CATEGORY_GROUPS).map(([key, group]) => (
            <option key={key} value={key}>
              {group.label}
            </option>
          ))}
        </select>
        <label className="shader-upload-btn">
          Upload .wgsl
          <input type="file" accept=".wgsl" onChange={handleUpload} hidden />
        </label>
      </div>

      <div className="shader-list">
        {loading ? (
          <div className="shader-loading">Loading shaders...</div>
        ) : filteredShaders.length === 0 ? (
          <div className="shader-empty">No shaders found</div>
        ) : (
          filteredShaders.map(shader => (
            <div 
              key={shader.id}
              className={`shader-card ${selectedId === shader.id ? 'selected' : ''}`}
              onClick={() => handleSelect(shader)}
            >
              <div className="shader-header">
                <h4>{shader.name}</h4>
                <div className="shader-stars">
                  {'★'.repeat(Math.round(shader.stars))}
                  {'☆'.repeat(5 - Math.round(shader.stars))}
                  <span className="shader-count">({shader.rating_count})</span>
                </div>
              </div>
              
              {editingId === shader.id ? (
                <div className="shader-edit-form" onClick={e => e.stopPropagation()}>
                  <textarea 
                    value={editDesc}
                    onChange={e => setEditDesc(e.target.value)}
                    placeholder="Edit description..."
                    rows={3}
                  />
                  <input 
                    value={editTags}
                    onChange={e => setEditTags(e.target.value)}
                    placeholder="Edit tags (comma-separated)..."
                  />
                  <div className="shader-edit-buttons">
                    <button onClick={() => saveEdit(shader.id)}>Save</button>
                    <button onClick={() => setEditingId(null)}>Cancel</button>
                  </div>
                </div>
              ) : (
                <>
                  <p className="shader-description">{shader.description}</p>
                  <div className="shader-tags">
                    {shader.tags.map(tag => (
                      <span key={tag} className="shader-tag">{tag}</span>
                    ))}
                  </div>
                  <button 
                    className="shader-edit-btn" 
                    onClick={e => { e.stopPropagation(); startEdit(shader); }}
                  >
                    Edit
                  </button>
                </>
              )}
              
              <div className="shader-rate" onClick={e => e.stopPropagation()}>
                <span>Rate:</span>
                {[1, 2, 3, 4, 5].map(stars => (
                  <button 
                    key={stars}
                    className="shader-star-btn"
                    onClick={e => handleRate(shader.id, stars, e)}
                  >
                    {stars}★
                  </button>
                ))}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
