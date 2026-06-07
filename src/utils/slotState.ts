import { RenderMode, SlotParams } from '../renderer/types';

export function withUpdatedMode(modes: RenderMode[], index: number, mode: RenderMode): RenderMode[] {
    const next = [...modes];
    next[index] = mode;
    return next;
}

export function withUpdatedSlotParams(
    params: SlotParams[],
    slotIndex: number,
    updates: Partial<SlotParams>
): SlotParams[] {
    const next = [...params];
    next[slotIndex] = { ...next[slotIndex], ...updates };
    return next;
}
