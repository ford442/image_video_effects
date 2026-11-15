/** stagePanelStore.ts — open / closed state of the stage-output panel (tiny; main bundle). */

type Listener = (open: boolean) => void;

let open = false;
const listeners = new Set<Listener>();

export const stagePanelStore = {
  isOpen: (): boolean => open,
  setOpen(next: boolean): void {
    if (next === open) return;
    open = next;
    for (const l of listeners) l(open);
  },
  toggle(): void {
    stagePanelStore.setOpen(!open);
  },
  subscribe(listener: Listener): () => void {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },
};
