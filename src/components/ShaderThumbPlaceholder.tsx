import React from 'react';
import {
  getCategoryGlyph,
  getCategoryPlaceholderStyle,
  truncateShaderName,
} from '../utils/thumbnailPlaceholder';
import './ShaderThumbPlaceholder.css';

export interface ShaderThumbPlaceholderProps {
  name: string;
  category?: string;
  className?: string;
  showName?: boolean;
}

export const ShaderThumbPlaceholder: React.FC<ShaderThumbPlaceholderProps> = ({
  name,
  category,
  className = '',
  showName = true,
}) => {
  const style = getCategoryPlaceholderStyle(category);
  return (
    <div
      className={`shader-thumb-placeholder ${className}`.trim()}
      style={{ background: style.background }}
      aria-label={`${name} — no preview`}
    >
      <span className="shader-thumb-placeholder-glyph" style={{ color: style.color }}>
        {getCategoryGlyph(category)}
      </span>
      {showName ? (
        <span className="shader-thumb-placeholder-name">{truncateShaderName(name)}</span>
      ) : null}
    </div>
  );
};
