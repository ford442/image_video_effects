import { useCallback, useEffect, useRef } from 'react';
import type { ChangeEvent } from 'react';

export type LocalMediaKind = 'image' | 'video';

/** Accept a file for `kind` when its MIME type matches (or is unknown — some OSes omit it). */
export function isAcceptedLocalMedia(file: Blob, kind: LocalMediaKind): boolean {
    return !file.type || file.type.startsWith(`${kind}/`);
}

/**
 * Shared plumbing for the hidden `<input type="file">` upload buttons in the main
 * app and the remote control. Picks the first file, resets the input (so choosing
 * the same file twice still fires `change`) and hands it to `onFile`.
 */
export function useLocalMediaUpload(
    onFile: (file: File, kind: LocalMediaKind) => void | Promise<void>,
): { handleFileChange: (e: ChangeEvent<HTMLInputElement>, kind: LocalMediaKind) => Promise<void> } {
    const onFileRef = useRef(onFile);
    onFileRef.current = onFile;

    const handleFileChange = useCallback(async (e: ChangeEvent<HTMLInputElement>, kind: LocalMediaKind) => {
        const input = e.target;
        const file = input.files?.[0];
        input.value = '';
        if (!file || !isAcceptedLocalMedia(file, kind)) return;
        await onFileRef.current(file, kind);
    }, []);

    return { handleFileChange };
}

export interface UseLocalMediaLoaderOptions {
    loadImage: (url: string) => void | Promise<void>;
    loadVideo: (url: string) => void | Promise<void>;
}

/**
 * Turns uploaded bytes into same-origin `blob:` URLs and feeds them to the media
 * loaders. Keeps one live URL per kind — the previous one is revoked when it is
 * replaced and everything is revoked on unmount.
 */
export function useLocalMediaLoader({ loadImage, loadVideo }: UseLocalMediaLoaderOptions): {
    loadLocalMedia: (blob: Blob, kind: LocalMediaKind) => Promise<void>;
} {
    const loadersRef = useRef({ loadImage, loadVideo });
    loadersRef.current = { loadImage, loadVideo };
    const urlsRef = useRef<Partial<Record<LocalMediaKind, string>>>({});

    useEffect(() => () => {
        const urls = urlsRef.current;
        if (urls.image) URL.revokeObjectURL(urls.image);
        if (urls.video) URL.revokeObjectURL(urls.video);
        urlsRef.current = {};
    }, []);

    const loadLocalMedia = useCallback(async (blob: Blob, kind: LocalMediaKind) => {
        if (!isAcceptedLocalMedia(blob, kind)) return;
        const url = URL.createObjectURL(blob);
        const previous = urlsRef.current[kind];
        urlsRef.current[kind] = url;
        const { loadImage: onImage, loadVideo: onVideo } = loadersRef.current;
        try {
            await (kind === 'image' ? onImage(url) : onVideo(url));
        } finally {
            if (previous) URL.revokeObjectURL(previous);
        }
    }, []);

    return { loadLocalMedia };
}
