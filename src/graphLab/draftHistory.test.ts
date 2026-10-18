import { canRedo, canUndo, COALESCE_MS, createHistory, HISTORY_LIMIT, pushHistory, redo, undo } from './draftHistory';

describe('draftHistory', () => {
  it('undoes and redoes edits; a new edit drops the redo stack', () => {
    let h = createHistory('a');
    h = pushHistory(h, 'b');
    h = pushHistory(h, 'c');
    h = undo(h);
    expect(h.present).toBe('b');
    expect(canRedo(h)).toBe(true);
    h = redo(h);
    expect(h.present).toBe('c');
    h = undo(undo(h));
    expect(h.present).toBe('a');
    expect(canUndo(h)).toBe(false);
    h = pushHistory(h, 'x');
    expect(canRedo(h)).toBe(false);
    expect(undo(h).present).toBe('a');
  });

  it('ignores no-op edits', () => {
    const h = createHistory('a');
    expect(pushHistory(h, 'a')).toBe(h);
  });

  it('folds rapid edits with the same coalesce key into one step', () => {
    let h = createHistory('');
    h = pushHistory(h, 'w', { coalesce: 'id', now: 1000 });
    h = pushHistory(h, 'wa', { coalesce: 'id', now: 1100 });
    h = pushHistory(h, 'wav', { coalesce: 'id', now: 1200 });
    expect(undo(h).present).toBe('');
    h = pushHistory(h, 'wave', { coalesce: 'id', now: 1200 + COALESCE_MS + 1 });
    expect(undo(h).present).toBe('wav');
    h = pushHistory(h, 'other', { coalesce: 'repeat', now: 1300 + COALESCE_MS });
    expect(undo(h).present).toBe('wave');
  });

  it('keeps at most HISTORY_LIMIT steps', () => {
    let h = createHistory(0);
    for (let i = 1; i <= HISTORY_LIMIT + 10; i++) h = pushHistory(h, i);
    expect(h.past).toHaveLength(HISTORY_LIMIT);
    expect(h.past[0]).toBe(10);
  });
});
