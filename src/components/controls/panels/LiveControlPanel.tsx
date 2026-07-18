import React, { Dispatch, SetStateAction } from 'react';
import { RenderMode } from '../../../renderer/types';
import {
    ControlBinding,
    ControlBindingRegistry,
    ControlAction,
    ControlTrigger,
} from '../../../services/controlBindings';
import { MIDIDevice } from '../../../services/midiControl';

export interface LiveControlPanelProps {
    liveControlOpen: boolean;
    setLiveControlOpen: Dispatch<SetStateAction<boolean>>;
    midiEnabled: boolean;
    setMidiEnabled: Dispatch<SetStateAction<boolean>>;
    midiDevices: MIDIDevice[];
    armed: null | 'midi' | 'key';
    setArmed: Dispatch<SetStateAction<null | 'midi' | 'key'>>;
    learnedTrigger: ControlTrigger | null;
    setLearnedTrigger: Dispatch<SetStateAction<ControlTrigger | null>>;
    pendingAction: ControlAction;
    setPendingAction: Dispatch<SetStateAction<ControlAction>>;
    pendingSlot: number;
    setPendingSlot: Dispatch<SetStateAction<number>>;
    pendingParam: string;
    setPendingParam: Dispatch<SetStateAction<string>>;
    bindings: ControlBinding[];
    setBindings: Dispatch<SetStateAction<ControlBinding[]>>;
    modes: RenderMode[];
}

export const LiveControlPanel: React.FC<LiveControlPanelProps> = ({
    liveControlOpen,
    setLiveControlOpen,
    midiEnabled,
    setMidiEnabled,
    midiDevices,
    armed,
    setArmed,
    learnedTrigger,
    setLearnedTrigger,
    pendingAction,
    setPendingAction,
    pendingSlot,
    setPendingSlot,
    pendingParam,
    setPendingParam,
    bindings,
    setBindings,
    modes,
}) => (
    <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
        <div
            className="gold-section-header"
            style={{ fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }}
            onClick={() => setLiveControlOpen(o => !o)}
        >
            <span>🎛️ Live Control</span>
            <span style={{ transform: liveControlOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>▼</span>
        </div>

        {liveControlOpen && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginTop: '10px' }}>
                <label style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: '12px' }}>
                    <span>Enable MIDI</span>
                    <input
                        type="checkbox"
                        checked={midiEnabled}
                        onChange={(e) => setMidiEnabled(e.target.checked)}
                    />
                </label>

                {midiEnabled && (
                    <div style={{ fontSize: '11px', color: '#a0a0b0' }}>
                        {midiDevices.length === 0 ? 'No MIDI devices detected.' : (
                            <ul style={{ margin: '4px 0', paddingLeft: '16px' }}>
                                {midiDevices.map(d => (
                                    <li key={d.id}>{d.name}</li>
                                ))}
                            </ul>
                        )}
                    </div>
                )}

                <div style={{ display: 'flex', gap: '8px' }}>
                    <button
                        className={`gold-outline-btn ${armed === 'midi' ? 'gold-active' : ''}`}
                        style={{ flex: 1, fontSize: '11px' }}
                        onClick={() => {
                            setArmed(armed === 'midi' ? null : 'midi');
                            setLearnedTrigger(null);
                        }}
                        disabled={!midiEnabled}
                    >
                        {armed === 'midi' ? ' Armed MIDI' : 'Arm MIDI'}
                    </button>
                    <button
                        className={`gold-outline-btn ${armed === 'key' ? 'gold-active' : ''}`}
                        style={{ flex: 1, fontSize: '11px' }}
                        onClick={() => {
                            setArmed(armed === 'key' ? null : 'key');
                            setLearnedTrigger(null);
                        }}
                    >
                        {armed === 'key' ? 'Armed Key' : 'Arm Key'}
                    </button>
                </div>

                {armed && (
                    <div style={{ fontSize: '11px', color: '#FFD700', textAlign: 'center' }}>
                        {armed === 'midi' ? 'Move a MIDI knob or press a pad…' : 'Press a key…'}
                    </div>
                )}

                {learnedTrigger && (
                    <div style={{ background: 'rgba(255,215,0,0.08)', border: '1px solid rgba(255,215,0,0.2)', borderRadius: '6px', padding: '10px' }}>
                        <div style={{ fontSize: '12px', color: '#FFD700', marginBottom: '8px' }}>
                            Captured: <code style={{ background: 'rgba(0,0,0,0.3)', padding: '2px 4px', borderRadius: '4px' }}>{learnedTrigger.source} {learnedTrigger.id}</code>
                        </div>

                        <label style={{ fontSize: '12px', display: 'block', marginBottom: '6px' }}>
                            Action
                            <select
                                className="glass-select"
                                style={{ width: '100%', marginTop: '4px' }}
                                value={pendingAction.type}
                                onChange={(e) => {
                                    const type = e.target.value as ControlAction['type'];
                                    if (type === 'setSlotParam') {
                                        setPendingAction({ type, slot: pendingSlot, param: pendingParam });
                                    } else if (type === 'randomizeSlot') {
                                        setPendingAction({ type, slot: pendingSlot });
                                    } else {
                                        setPendingAction({ type } as ControlAction);
                                    }
                                }}
                            >
                                <option value="setSlotParam">Set Slot Parameter</option>
                                <option value="randomizeSlot">Randomize Slot</option>
                                <option value="randomizeAll">Randomize All Slots</option>
                                <option value="triggerTransition">Trigger Transition</option>
                                <option value="toggleAutoTransition">Toggle Auto Transition</option>
                            </select>
                        </label>

                        {(pendingAction.type === 'setSlotParam' || pendingAction.type === 'randomizeSlot') && (
                            <label style={{ fontSize: '12px', display: 'block', marginBottom: '6px' }}>
                                Slot
                                <select
                                    className="glass-select"
                                    style={{ width: '100%', marginTop: '4px' }}
                                    value={pendingSlot}
                                    onChange={(e) => {
                                        const slot = Number(e.target.value);
                                        setPendingSlot(slot);
                                        if (pendingAction.type === 'setSlotParam') {
                                            setPendingAction({ ...pendingAction, slot });
                                        } else if (pendingAction.type === 'randomizeSlot') {
                                            setPendingAction({ ...pendingAction, slot });
                                        }
                                    }}
                                >
                                    {modes.map((_, i) => (
                                        <option key={i} value={i}>Slot {i + 1}</option>
                                    ))}
                                </select>
                            </label>
                        )}

                        {pendingAction.type === 'setSlotParam' && (
                            <label style={{ fontSize: '12px', display: 'block', marginBottom: '10px' }}>
                                Parameter
                                <select
                                    className="glass-select"
                                    style={{ width: '100%', marginTop: '4px' }}
                                    value={pendingParam}
                                    onChange={(e) => {
                                        const param = e.target.value;
                                        setPendingParam(param);
                                        setPendingAction({ ...pendingAction, param });
                                    }}
                                >
                                    <option value="zoomParam1">Zoom Param 1</option>
                                    <option value="zoomParam2">Zoom Param 2</option>
                                    <option value="zoomParam3">Zoom Param 3</option>
                                    <option value="zoomParam4">Zoom Param 4</option>
                                    <option value="lightStrength">Light Strength</option>
                                    <option value="ambient">Ambient</option>
                                    <option value="normalStrength">Normal Strength</option>
                                    <option value="fogFalloff">Fog Falloff</option>
                                    <option value="depthThreshold">Depth Threshold</option>
                                </select>
                            </label>
                        )}

                        <div style={{ display: 'flex', gap: '8px' }}>
                            <button
                                className="gold-outline-btn"
                                style={{ flex: 1, fontSize: '11px' }}
                                onClick={() => {
                                    if (!learnedTrigger) return;
                                    setBindings(prev => {
                                        const registry = new ControlBindingRegistry(prev);
                                        registry.addBinding(learnedTrigger, pendingAction);
                                        return registry.getBindings();
                                    });
                                    setLearnedTrigger(null);
                                }}
                            >
                                Save Binding
                            </button>
                            <button
                                className="gold-outline-btn"
                                style={{ fontSize: '11px' }}
                                onClick={() => setLearnedTrigger(null)}
                            >
                                Cancel
                            </button>
                        </div>
                    </div>
                )}

                {bindings.length > 0 && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '6px' }}>
                        <div style={{ fontSize: '11px', color: '#a0a0b0' }}>Bindings ({bindings.length})</div>
                        {bindings.map((binding, idx) => (
                            <div
                                key={`${binding.trigger.source}-${binding.trigger.id}-${idx}`}
                                style={{
                                    display: 'flex',
                                    justifyContent: 'space-between',
                                    alignItems: 'center',
                                    background: 'rgba(20,20,30,0.6)',
                                    border: '1px solid rgba(255,215,0,0.1)',
                                    borderRadius: '6px',
                                    padding: '6px 8px',
                                    fontSize: '11px',
                                }}
                            >
                                <div>
                                    <span style={{ color: '#FFD700', fontFamily: 'monospace' }}>{binding.trigger.id}</span>
                                    <span style={{ color: '#a0a0b0', marginLeft: '6px' }}>
                                        → {binding.action.type === 'setSlotParam'
                                            ? `set slot ${binding.action.slot}.${binding.action.param}`
                                            : binding.action.type === 'randomizeSlot'
                                                ? `randomize slot ${binding.action.slot}`
                                                : binding.action.type.replace(/([A-Z])/g, ' $1').toLowerCase()}
                                    </span>
                                </div>
                                <button
                                    className="gold-outline-btn"
                                    style={{ fontSize: '10px', padding: '2px 6px' }}
                                    onClick={() => {
                                        setBindings(prev => {
                                            const registry = new ControlBindingRegistry(prev);
                                            registry.removeBinding(binding.trigger);
                                            return registry.getBindings();
                                        });
                                    }}
                                >
                                    ✕
                                </button>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        )}
    </div>
);

export default LiveControlPanel;
