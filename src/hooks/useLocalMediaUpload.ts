import { useCallback, useRef } from 'react';
import type { ChangeEvent } from 'react';

export type LocalMediaKind = 'image' | 'video';

/** Receives the chosen file; App loads it locally, RemoteApp forwards it to the main window. */
export type LocalMediaLoader = (file: File, kind: LocalMediaKind) => void | Promise<void>;

export interface LocalMediaUploadHandlers {
    onImageChange: (event: ChangeEvent<HTMLInputElement>) => void;
    onVideoChange: (event: ChangeEvent<HTMLInputElement>) => void;
}

/**
 * onChange handlers for the hidden `<input type="file">` upload pickers (#1511 bug 1).
 * The input value is reset after each pick so choosing the same file again fires a change.
 */
export function useLocalMediaUpload(loader: LocalMediaLoader): LocalMediaUploadHandlers {
    const loaderRef = useRef(loader);
    loaderRef.current = loader;

    const handle = useCallback((event: ChangeEvent<HTMLInputElement>, kind: LocalMediaKind) => {
        const input = event.target;
        const file = input.files?.[0];
        input.value = '';
        if (!file) return;
        Promise.resolve(loaderRef.current(file, kind)).catch((err) => {
            console.error(`[Upload] Failed to load ${kind} "${file.name}":`, err);
        });
    }, []);

    const onImageChange = useCallback((event: ChangeEvent<HTMLInputElement>) => handle(event, 'image'), [handle]);
    const onVideoChange = useCallback((event: ChangeEvent<HTMLInputElement>) => handle(event, 'video'), [handle]);

    return { onImageChange, onVideoChange };
}
