import { useEffect } from 'react';
import { InputSource } from '../renderer/types';
import { VideoRecord } from '../syncTypes';
import { mergeDurations, probeVideoDuration } from '../services/videoSegmentManager';

export interface UseSelectedVideoDurationOptions {
    inputSource: InputSource;
    selectedVideo: string;
    videoList: VideoRecord[];
    setVideoList: React.Dispatch<React.SetStateAction<VideoRecord[]>>;
}

/**
 * Probe the duration of the video the user actually picked, if the manifest
 * didn't carry one. Nothing is requested while another source is active.
 */
export function useSelectedVideoDuration({
    inputSource,
    selectedVideo,
    videoList,
    setVideoList,
}: UseSelectedVideoDurationOptions): void {
    const needsProbe =
        inputSource === 'video' &&
        videoList.some(
            (v) => v.url === selectedVideo && !(typeof v.duration === 'number' && v.duration > 0)
        );

    useEffect(() => {
        if (!needsProbe) return;
        let cancelled = false;
        void probeVideoDuration(selectedVideo).then((duration) => {
            if (cancelled || duration === undefined) return;
            setVideoList((current) =>
                mergeDurations(current, [{ url: selectedVideo, duration }])
            );
        });
        return () => {
            cancelled = true;
        };
    }, [needsProbe, selectedVideo, setVideoList]);
}
