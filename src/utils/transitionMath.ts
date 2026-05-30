export interface ParamConstraint {
  min: number;
  max: number;
  step?: number;
}

export type ParamMap = Record<string, number>;
export type ParamMapSchema = Record<string, ParamConstraint>;

const clamp = (value: number, min: number, max: number): number => Math.max(min, Math.min(max, value));

export function easeInOutSine(x: number): number {
  const clamped = clamp(x, 0, 1);
  return -(Math.cos(Math.PI * clamped) - 1) / 2;
}

export function lerpParam(
  current: number,
  target: number,
  progress: number,
  min: number,
  max: number
): number {
  const eased = easeInOutSine(progress);
  const value = current + (target - current) * eased;
  return clamp(value, min, max);
}

export function snapToStep(value: number, min: number, max: number, step?: number): number {
  const clamped = clamp(value, min, max);
  if (!step || step <= 0) return clamped;
  const snapped = min + Math.round((clamped - min) / step) * step;
  return clamp(snapped, min, max);
}

export function lerpParamMap(
  current: ParamMap,
  target: ParamMap,
  progress: number,
  schema: ParamMapSchema
): ParamMap {
  const output: ParamMap = {};
  const keys = new Set([...Object.keys(current), ...Object.keys(target)]);
  for (const key of keys) {
    const currentValue = current[key];
    const targetValue = target[key];
    const rule = schema[key];
    if (typeof currentValue === 'number' && typeof targetValue === 'number' && rule) {
      output[key] = lerpParam(currentValue, targetValue, progress, rule.min, rule.max);
      continue;
    }
    if (typeof targetValue === 'number') {
      output[key] = rule ? clamp(targetValue, rule.min, rule.max) : targetValue;
      continue;
    }
    if (typeof currentValue === 'number') {
      output[key] = rule ? clamp(currentValue, rule.min, rule.max) : currentValue;
    }
  }
  return output;
}

