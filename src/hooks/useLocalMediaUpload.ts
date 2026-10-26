import { useCallback, useEffect, useRef, type ChangeEvent } from 'react';

export type LocalMediaKind = 'image' | 'video';

/** Receives the picked file. The main app loads it; the remote forwards it to the main app. */
export type LocalMediaHandler = (file: Blob, kind: LocalMediaKind) => void | Promise<void>;

/**
 * The hidden `<input type="file">` change handler shared by App and RemoteApp: take the first
 * picked file, reset the input (so picking the same file again still fires), hand it on.
 */
export function useLocalMediaUpload(onFile: LocalMediaHandler) {
    const handleFileChange = useCallback((e: ChangeEvent<HTMLInputElement>, kind: LocalMediaKind) => {
        const input = e.target;
        const file = input.files?.[0];
        input.value = '';
        if (!file) return;
        void Promise.resolve()
            .then(() => onFile(file, kind))
            .catch((err: unknown) => console.error(`[LocalMediaUpload] ${kind} upload failed:`, err));
    }, [onFile]);

    return { handleFileChange };
}

export interface UseLocalMediaLoaderOptions {
    /** Load an image URL into the renderer (blob: URL of the picked file). */
    onImage: (url: string) => void | Promise<void>;
    /** Play a video URL as the input source (blob: URL of the picked file). */
    onVideo: (url: string) => void;
}

/**
 * Turns a picked (or remotely sent) file into a blob: URL for the renderer. Each kind keeps
 * one live URL: the previous one is revoked when a new file of that kind replaces it, and all
 * are revoked on unmount. The image URL stays alive while current because depth analysis
 * re-reads it.
 */
export function useLocalMediaLoader({ onImage, onVideo }: UseLocalMediaLoaderOptions): LocalMediaHandler {
    const urls = useRef<Partial<Record<LocalMediaKind, string>>>({});

    useEffect(() => {
        const live = urls.current;
        return () => {
            for (const url of Object.values(live)) if (url) URL.revokeObjectURL(url);
        };
    }, []);

    return useCallback(async (file: Blob, kind: LocalMediaKind) => {
        const url = URL.createObjectURL(file);
        const previous = urls.current[kind];
        urls.current[kind] = url;
        if (previous) URL.revokeObjectURL(previous);
        if (kind === 'image') await onImage(url);
        else onVideo(url);
    }, [onImage, onVideo]);
}
