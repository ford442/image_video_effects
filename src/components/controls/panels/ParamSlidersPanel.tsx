import React from 'react';
import { ShaderEntry, SlotParams } from '../../../renderer/types';

export interface ParamSlidersPanelProps {
    activeSlot: number;
    currentShaderEntry: ShaderEntry | undefined;
    currentParams: SlotParams;
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
}

export const ParamSlidersPanel: React.FC<ParamSlidersPanelProps> = ({
    activeSlot,
    currentShaderEntry,
    currentParams,
    updateSlotParam,
}) => (
    <>
        <div className="gold-section-header">
            Shader Parameters
            <span style={{ fontWeight: 'normal', color: '#a0a0b0', marginLeft: '8px', fontSize: '12px' }}>
                {currentShaderEntry?.name || 'None'}
            </span>
        </div>

        <div className="params-grid">
            {currentShaderEntry?.params?.map((param, index) => {
                if (index > 3) return null;

                let val = 0;
                if (index === 0) val = currentParams.zoomParam1;
                else if (index === 1) val = currentParams.zoomParam2;
                else if (index === 2) val = currentParams.zoomParam3;
                else if (index === 3) val = currentParams.zoomParam4;

                return (
                    <div key={param.id} className="control-group">
                        <label htmlFor={`param-${param.id}`} style={{ display: 'flex', justifyContent: 'space-between', color: '#a0a0b0' }}>
                            <span>{param.name}</span>
                            <span style={{ color: '#FFD700', fontSize: '11px', fontWeight: 500 }}>{val.toFixed(2)}</span>
                        </label>
                        <input
                            id={`param-${param.id}`}
                            type="range"
                            className="glass-range"
                            min={param.min}
                            max={param.max}
                            step={param.step || 0.01}
                            value={val}
                            onChange={(e) => {
                                const v = parseFloat(e.target.value);
                                const update: Partial<SlotParams> = {};
                                if (index === 0) update.zoomParam1 = v;
                                else if (index === 1) update.zoomParam2 = v;
                                else if (index === 2) update.zoomParam3 = v;
                                else if (index === 3) update.zoomParam4 = v;
                                updateSlotParam(activeSlot, update);
                            }}
                        />
                    </div>
                );
            })}
        </div>

        {currentShaderEntry?.params && currentShaderEntry.params.length > 4 && (
            <div style={{ color: '#a0a0b0', fontStyle: 'italic', padding: '5px 0', fontSize: '11px', textAlign: 'center' }}>
                Showing 4 of {currentShaderEntry.params.length} parameters (renderer limit)
            </div>
        )}

        {currentShaderEntry && (!currentShaderEntry.params || currentShaderEntry.params.length === 0) && (
            <>
                <div style={{ color: '#a0a0b0', fontStyle: 'italic', padding: '5px 0', fontSize: '11px', textAlign: 'center' }}>
                    Generic parameters for <code style={{ color: '#FFD700' }}>{currentShaderEntry.id}</code>
                </div>
                <div className="params-grid">
                    {([
                        { id: 'fallback1', name: 'Param 1', paramKey: 'zoomParam1' as const },
                        { id: 'fallback2', name: 'Param 2', paramKey: 'zoomParam2' as const },
                        { id: 'fallback3', name: 'Param 3', paramKey: 'zoomParam3' as const },
                        { id: 'fallback4', name: 'Param 4', paramKey: 'zoomParam4' as const },
                    ]).map((fb) => {
                        const val = currentParams[fb.paramKey];
                        return (
                            <div key={fb.id} className="control-group">
                                <label htmlFor={`param-${fb.id}`} style={{ display: 'flex', justifyContent: 'space-between', color: '#a0a0b0' }}>
                                    <span>{fb.name}</span>
                                    <span style={{ color: '#FFD700', fontSize: '11px', fontWeight: 500 }}>{val.toFixed(2)}</span>
                                </label>
                                <input
                                    id={`param-${fb.id}`}
                                    type="range"
                                    className="glass-range"
                                    min={0}
                                    max={1}
                                    step={0.01}
                                    value={val}
                                    onChange={(e) => {
                                        updateSlotParam(activeSlot, { [fb.paramKey]: parseFloat(e.target.value) });
                                    }}
                                />
                            </div>
                        );
                    })}
                </div>
            </>
        )}

        {!currentShaderEntry && (
            <div className="glass-card" style={{ textAlign: 'center', padding: '15px', color: '#a0a0b0', fontStyle: 'italic' }}>
                Select an effect for this slot to see parameters.
            </div>
        )}
    </>
);

export default ParamSlidersPanel;
