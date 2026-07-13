import React from 'react';
import { ShaderEntry } from '../../../renderer/types';
import { ShaderStarRating } from '../../ShaderStarRating';

export interface CoordinateDisplayPanelProps {
    currentCoordinate: number;
    currentShaderEntry?: ShaderEntry;
    currentMode: string;
    getZoneColor: (coord: number) => string;
    ratingStars: number;
    ratingCount: number;
    onRate: (id: string, stars: number) => Promise<void>;
}

export const CoordinateDisplayPanel: React.FC<CoordinateDisplayPanelProps> = ({
    currentCoordinate,
    currentShaderEntry,
    currentMode,
    getZoneColor,
    ratingStars,
    ratingCount,
    onRate,
}) => (
    <div
        className="glass-card"
        style={{
            borderColor: getZoneColor(currentCoordinate),
            background: `${getZoneColor(currentCoordinate)}15`,
            marginBottom: '12px',
        }}
    >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: '12px', color: '#a0a0b0' }}>Current Shader</span>
            <span
                className="coordinate-badge"
                style={{
                    color: getZoneColor(currentCoordinate),
                    borderColor: `${getZoneColor(currentCoordinate)}40`,
                    background: `${getZoneColor(currentCoordinate)}15`,
                }}
            >
                #{currentCoordinate}
            </span>
        </div>
        <div style={{ fontSize: '13px', color: '#f0f0f5', marginTop: '6px', fontWeight: 500 }}>
            {currentShaderEntry?.name}
        </div>
        {currentMode && (
            <div style={{ marginTop: '8px' }}>
                <ShaderStarRating
                    shaderId={currentMode}
                    stars={ratingStars}
                    ratingCount={ratingCount}
                    onRate={onRate}
                    size="small"
                />
            </div>
        )}
    </div>
);

export default CoordinateDisplayPanel;
