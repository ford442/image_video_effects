/** external.ts — controlBindings (MIDI CC / note / keys, OSC adapters) → the bus's external source. */

import { addControlEventTap, type ControlEvent } from '../services/controlBindings';
import { modulationStore } from './store';

export const externalKey = (event: Pick<ControlEvent, 'source' | 'id'>): string => `${event.source}:${event.id}`;

/** Feed every dispatched control event into the bus. Returns the disconnect function. */
export function connectControlEventsToModulation(): () => void {
  return addControlEventTap((event) => modulationStore.setExternal({ [externalKey(event)]: event.value }));
}
