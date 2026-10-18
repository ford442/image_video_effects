import { useEffect, useRef } from 'react';
import { InputSource } from '../renderer/types';
import { VideoRecord } from '../syncTypes';
import { VideoSegment, hydrateDurations, pickRandomSegment } from '../services/videoSegmentManager';

export interface UseB3hdModeOptions {
    videoB3hdMode: boolean;
    inputSource: InputSource;
    videoList: VideoRecord[];
    b3hdSegmentLength: number;
    b3hdIntervalSeconds: number;
    setCurrentSegment: React.Dispatch<React.SetStateAction<VideoSegment | null>>;
    setSelectedVideo: React.Dispatch<React.SetStateAction<string>>;
    /** Receives the list with probed durations once B3HD needs them. */
    setVideoList?: React.Dispatch<React.SetStateAction<VideoRecord[]>>;
}

const hasDuration = (v: VideoRecord) => typeof v.duration === 'number' && v.duration > 0;

export function useB3hdMode({
    videoB3hdMode,
    inputSource,
    videoList,
    b3hdSegmentLength,
    b3hdIntervalSeconds,
    setCurrentSegment,
    setSelectedVideo,
    setVideoList,
}: UseB3hdModeOptions): void {
    const b3hdTimerRef = useRef<NodeJS.Timeout | null>(null);
    const b3hdRecentHistoryRef = useRef<string[]>([]);
    const videoListRef = useRef<VideoRecord[]>(videoList);
    videoListRef.current = videoList;

    useEffect(() => {
        if (b3hdTimerRef.current) {
            clearTimeout(b3hdTimerRef.current);
            b3hdTimerRef.current = null;
        }

        if (!videoB3hdMode || inputSource !== 'video' || videoList.length === 0) {
            setCurrentSegment(null);
            return;
        }

        const playNextSegment = () => {
            const segment = pickRandomSegment(
                videoListRef.current,
                b3hdSegmentLength,
                b3hdRecentHistoryRef.current
            );
            if (!segment) {
                console.warn("B3HD: No valid segment found");
                return;
            }

            setCurrentSegment(segment);
            setSelectedVideo(segment.video.url);

            b3hdRecentHistoryRef.current.push(segment.video.id || segment.video.url);
            if (b3hdRecentHistoryRef.current.length > 5) {
                b3hdRecentHistoryRef.current.shift();
            }

            const totalCycle = (b3hdSegmentLength + b3hdIntervalSeconds) * 1000;
            b3hdTimerRef.current = setTimeout(playNextSegment, totalCycle);
        };

        // Segment picking needs durations; probe them only now, not at boot.
        let cancelled = false;
        const start = async () => {
            if (!videoListRef.current.every(hasDuration)) {
                const hydrated = await hydrateDurations(videoListRef.current);
                if (cancelled) return;
                videoListRef.current = hydrated;
                if (setVideoList) {
                    const byUrl = new Map(hydrated.map((v) => [v.url, v.duration]));
                    setVideoList((prev) => prev.map((v) => {
                        const duration = byUrl.get(v.url);
                        return hasDuration(v) || duration === undefined ? v : { ...v, duration };
                    }));
                }
            }
            if (!cancelled) playNextSegment();
        };
        void start();

        return () => {
            cancelled = true;
            if (b3hdTimerRef.current) {
                clearTimeout(b3hdTimerRef.current);
                b3hdTimerRef.current = null;
            }
        };
    }, [videoB3hdMode, inputSource, b3hdSegmentLength, b3hdIntervalSeconds, videoList.length, setCurrentSegment, setSelectedVideo, setVideoList]);
}
