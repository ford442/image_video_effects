import React, { useEffect } from 'react';
import type { ErrorNotice } from '../../renderer/errorNotices';

export interface RendererErrorNoticeProps {
    notice: ErrorNotice | null;
    onDismiss: () => void;
    /** Pick a different effect for the active slot (shader failures). */
    onTryAnotherEffect: () => void;
    /** Load a different random image (image failures; only offered while the Image source is active). */
    onTryAnotherImage?: () => void;
    /** Switch to the generative source, which needs no media host. */
    onUseGenerative: () => void;
}

const AUTO_DISMISS_MS = 20_000;

/** Friendly, dismissible error banner over the canvas with a recovery action. */
export const RendererErrorNotice: React.FC<RendererErrorNoticeProps> = ({
    notice,
    onDismiss,
    onTryAnotherEffect,
    onTryAnotherImage,
    onUseGenerative,
}) => {
    useEffect(() => {
        if (!notice) return undefined;
        const t = window.setTimeout(onDismiss, AUTO_DISMISS_MS);
        return () => window.clearTimeout(t);
    }, [notice, onDismiss]);

    if (!notice) return null;

    const act = (fn: () => void) => () => {
        onDismiss();
        fn();
    };

    return (
        <div className="renderer-error-notice" role="alert" data-testid="renderer-error-notice" data-kind={notice.kind}>
            <span className="renderer-error-notice__text">{notice.message}</span>
            <span className="renderer-error-notice__actions">
                {notice.kind === 'shader' && (
                    <button type="button" onClick={act(onTryAnotherEffect)}>Try another effect</button>
                )}
                {notice.kind === 'image' && onTryAnotherImage && (
                    <button type="button" onClick={act(onTryAnotherImage)}>Try another image</button>
                )}
                {(notice.kind === 'image' || notice.kind === 'video') && (
                    <button type="button" onClick={act(onUseGenerative)}>Use generative source</button>
                )}
                <button type="button" className="renderer-error-notice__dismiss" aria-label="Dismiss" onClick={onDismiss}>
                    ✕
                </button>
            </span>
        </div>
    );
};

export default RendererErrorNotice;
