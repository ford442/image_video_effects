import React from 'react';
import { ShaderEntry, SlotParams } from '../../../renderer/types';
import { shouldShowMidiControls } from '../../../utils/deviceCapabilities';

const INDEX_TO_PARAM: Array<keyof SlotParams> = ['zoomParam1', 'zoomParam2', 'zoomParam3', 'zoomParam4'];

export interface ParamSlidersPanelProps {
    activeSlot: number;
    currentShaderEntry: ShaderEntry | undefined;
    currentParams: SlotParams;
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    onStartMidiLearn?: (slot: number, param: keyof SlotParams) => void;
    learnActiveParam?: string | null;
}

function MidiLearnButton({
    paramKey,
    activeSlot,
    learnActiveParam,
    onStartMidiLearn,
}: {
    paramKey: keyof SlotParams;
    activeSlot: number;
    learnActiveParam?: string | null;
    onStartMidiLearn?: (slot: number, param: keyof SlotParams) => void;
}) {
    if (!shouldShowMidiControls() || !onStartMidiLearn) return null;
    const isActive = learnActiveParam === paramKey;
    return (
        <button
            type="button"
            className={`gold-outline-btn ${isActive ? 'gold-active' : ''}`}
            style={{ fontSize: '10px', padding: '2px 6px', marginLeft: '6px' }}
            title="Map MIDI to this parameter"
            onClick={() => onStartMidiLearn(activeSlot, paramKey)}
        >
            🎛
        </button>
    );
}

export const ParamSlidersPanel: React.FC<ParamSlidersPanelProps> = ({
    activeSlot,
    currentShaderEntry,
    currentParams,
    updateSlotParam,
    onStartMidiLearn,
    learnActiveParam,
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

                const paramKey = INDEX_TO_PARAM[index];
                const val = currentParams[paramKey];

                return (
                    <div key={param.id} className="control-group">
                        <label htmlFor={`param-${param.id}`} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#a0a0b0' }}>
                            <span style={{ display: 'flex', alignItems: 'center' }}>
                                {param.name}
                                <MidiLearnButton paramKey={paramKey} activeSlot={activeSlot} learnActiveParam={learnActiveParam} onStartMidiLearn={onStartMidiLearn} />
                            </span>
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
                                updateSlotParam(activeSlot, { [paramKey]: parseFloat(e.target.value) });
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
                                <label htmlFor={`param-${fb.id}`} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#a0a0b0' }}>
                                    <span style={{ display: 'flex', alignItems: 'center' }}>
                                        {fb.name}
                                        <MidiLearnButton paramKey={fb.paramKey} activeSlot={activeSlot} learnActiveParam={learnActiveParam} onStartMidiLearn={onStartMidiLearn} />
                                    </span>
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
