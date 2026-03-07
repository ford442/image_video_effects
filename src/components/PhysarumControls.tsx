import React, { useState, useCallback } from 'react';

interface PhysarumControlsProps {
  onParamChange: (name: string, value: number) => void;
}

interface ParamConfig {
  name: string;
  label: string;
  min: number;
  max: number;
  step: number;
  defaultValue: number;
  unit?: string;
}

const PARAMS: ParamConfig[] = [
  { name: 'sensorAngle', label: 'Sensor Angle', min: 0, max: 90, step: 1, defaultValue: 45, unit: '°' },
  { name: 'sensorDist', label: 'Sensor Distance', min: 1, max: 50, step: 1, defaultValue: 9, unit: 'px' },
  { name: 'turnSpeed', label: 'Turn Speed', min: 0, max: 0.5, step: 0.01, defaultValue: 0.1 },
  { name: 'decayRate', label: 'Decay Rate', min: 0.8, max: 0.99, step: 0.01, defaultValue: 0.95 },
  { name: 'depositAmount', label: 'Deposit', min: 0.1, max: 10, step: 0.1, defaultValue: 0.5 },
  { name: 'agentCount', label: 'Agent Count', min: 1000, max: 100000, step: 1000, defaultValue: 50000, unit: '' },
  { name: 'videoFoodStrength', label: 'Video Food', min: 0, max: 1, step: 0.05, defaultValue: 0.3 },
  { name: 'audioPulseStrength', label: 'Audio React', min: 0, max: 1, step: 0.05, defaultValue: 0.5 },
  { name: 'mouseAttraction', label: 'Mouse Attract', min: -1, max: 1, step: 0.1, defaultValue: 0.5 },
  // Raptor Mini specific additions
  { name: 'maxSpeed', label: 'Max Speed', min: 1, max: 5, step: 0.1, defaultValue: 3 },
  { name: 'rageDuration', label: 'Rage Duration', min: 0.5, max: 5, step: 0.1, defaultValue: 1.2 },
  { name: 'rageSpeedBoost', label: 'Rage Boost', min: 1, max: 3, step: 0.1, defaultValue: 2 },
  { name: 'clawProb', label: 'Claw Prob', min: 0, max: 0.1, step: 0.005, defaultValue: 0.02 },
  { name: 'scalePatternSize', label: 'Scale Size', min: 1, max: 10, step: 1, defaultValue: 4 },
  { name: 'preyAttraction', label: 'Prey Attract', min: 0, max: 2, step: 0.1, defaultValue: 1.5 },
  { name: 'neighborCohesion', label: 'Neighbor Cohesion', min: 0, max: 1, step: 0.05, defaultValue: 0.3 },
];

const PRESETS = {
  gentle: { sensorAngle: 30, sensorDist: 15, turnSpeed: 0.05, decayRate: 0.98, depositAmount: 0.3 },
  chaotic: { sensorAngle: 60, sensorDist: 5, turnSpeed: 0.2, decayRate: 0.9, depositAmount: 1.0 },
  audio: { sensorAngle: 45, sensorDist: 9, turnSpeed: 0.1, decayRate: 0.95, depositAmount: 0.5, audioPulseStrength: 0.9 },
};

export const PhysarumControls: React.FC<PhysarumControlsProps> = ({ onParamChange }) => {
  const [values, setValues] = useState<Record<string, number>>(() => {
    const defaults: Record<string, number> = {};
    PARAMS.forEach(p => defaults[p.name] = p.defaultValue);
    return defaults;
  });

  const handleChange = useCallback((name: string, value: number) => {
    setValues(prev => ({ ...prev, [name]: value }));
    onParamChange(name, value);
  }, [onParamChange]);

  const applyPreset = useCallback((presetName: keyof typeof PRESETS) => {
    const preset = PRESETS[presetName];
    Object.entries(preset).forEach(([name, value]) => {
      handleChange(name, value);
    });
  }, [handleChange]);

  const resetToDefaults = useCallback(() => {
    PARAMS.forEach(p => {
      handleChange(p.name, p.defaultValue);
    });
  }, [handleChange]);

  return (
    <div style={styles.container}>
      {/* Preset Buttons */}
      <div style={styles.presets}>
        <button style={styles.presetBtn} onClick={() => applyPreset('gentle')}>
          🌊 Gentle
        </button>
        <button style={styles.presetBtn} onClick={() => applyPreset('chaotic')}>
          🔥 Chaotic
        </button>
        <button style={styles.presetBtn} onClick={() => applyPreset('audio')}>
          🎵 Audio
        </button>
        <button style={{ ...styles.presetBtn, opacity: 0.7 }} onClick={resetToDefaults}>
          ↺ Reset
        </button>
      </div>

      {/* Sliders */}
      <div style={styles.sliders}>
        {PARAMS.map(param => (
          <div key={param.name} style={styles.control}>
            <div style={styles.controlHeader}>
              <label style={styles.label}>{param.label}</label>
              <span style={styles.value}>
                {values[param.name].toFixed(param.step < 1 ? 2 : 0)}{param.unit}
              </span>
            </div>
            <input
              type="range"
              min={param.min}
              max={param.max}
              step={param.step}
              value={values[param.name]}
              onChange={(e) => handleChange(param.name, parseFloat(e.target.value))}
              style={styles.slider}
            />
          </div>
        ))}
      </div>
    </div>
  );
};

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
  },
  presets: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: '8px',
  },
  presetBtn: {
    padding: '6px 12px',
    background: '#1e1e32',
    border: '1px solid #2a2a4a',
    borderRadius: '6px',
    color: '#fff',
    cursor: 'pointer',
    fontSize: '12px',
    flex: 1,
    minWidth: '60px',
  },
  sliders: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  control: {
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
  },
  controlHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  label: {
    fontSize: '12px',
    color: '#8b8ba7',
  },
  value: {
    fontSize: '12px',
    color: '#00d4ff',
    fontFamily: 'monospace',
    fontWeight: 600,
  },
  slider: {
    width: '100%',
    height: '4px',
    background: '#1e1e32',
    borderRadius: '2px',
    outline: 'none',
    cursor: 'pointer',
    appearance: 'none',
  },
};

export default PhysarumControls;
