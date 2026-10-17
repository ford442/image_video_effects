import { useCallback, useState } from 'react';
import type { Dispatch, SetStateAction } from 'react';

const PREFIX = 'pixelocity.ui.';

function readStored(key: string): boolean | null {
    if (typeof localStorage === 'undefined') return null;
    try {
        const raw = localStorage.getItem(PREFIX + key);
        if (raw === '1') return true;
        if (raw === '0') return false;
    } catch {
        // ignore privacy / quota errors
    }
    return null;
}

function writeStored(key: string, value: boolean): void {
    if (typeof localStorage === 'undefined') return;
    try {
        localStorage.setItem(PREFIX + key, value ? '1' : '0');
    } catch {
        // ignore
    }
}

/**
 * `useState<boolean>` that remembers its value in localStorage. Only explicit
 * toggles are written, so a stored value always wins over a (possibly
 * state-dependent) default and an untouched section keeps following its default.
 */
export function usePersistedToggle(
    key: string,
    initial: boolean | (() => boolean),
): [boolean, Dispatch<SetStateAction<boolean>>] {
    const [value, setValue] = useState<boolean>(
        () => readStored(key) ?? (typeof initial === 'function' ? initial() : initial),
    );
    const set = useCallback<Dispatch<SetStateAction<boolean>>>((next) => {
        setValue((prev) => {
            const resolved = typeof next === 'function' ? next(prev) : next;
            writeStored(key, resolved);
            return resolved;
        });
    }, [key]);
    return [value, set];
}
