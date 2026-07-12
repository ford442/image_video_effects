import React from 'react';
import { ShaderCategory } from '../../../renderer/types';

export interface EffectCategoryPanelProps {
    shaderCategory: ShaderCategory;
    setShaderCategory: (category: ShaderCategory) => void;
}

export const EffectCategoryPanel: React.FC<EffectCategoryPanelProps> = ({
    shaderCategory,
    setShaderCategory,
}) => (
    <div className="control-group">
        <label htmlFor="category-select" className="gold-section-header" style={{ fontSize: '13px' }}>Effect Filter</label>
        <select
            id="category-select"
            className="glass-select"
            value={shaderCategory}
            onChange={(e) => setShaderCategory(e.target.value as ShaderCategory)}
        >
            <option value="image">All Effects / Filters</option>
            <option value="generative">Procedural Generation</option>
            <option value="distortion">Distortion</option>
            <option value="simulation">Simulation</option>
            <option value="artistic">Artistic</option>
            <option value="interactive-mouse">Interactive / Mouse</option>
            <option value="lighting-effects">Lighting Effects</option>
            <option value="liquid-effects">Liquid Effects</option>
            <option value="retro-glitch">Retro / Glitch</option>
            <option value="visual-effects">Visual Effects</option>
            <option value="geometric">Geometric</option>
            <option value="post-processing">Post-Processing</option>
        </select>
    </div>
);

export default EffectCategoryPanel;
