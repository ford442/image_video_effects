import { useEffect, useRef } from 'react';
import { InputSource } from '../renderer/types';
import { VideoRecord } from '../syncTypes';
import { VideoSegment, pickRandomSegment } from '../services/videoSegmentManager';

export interface UseB3hdModeOptions {
    videoB3hdMode: boolean;
    inputSource: InputSource;
    videoList: VideoRecord[];
    b3hdSegmentLength: number;
    b3hdIntervalSeconds: number;
    setCurrentSegment: React.Dispatch<React.SetStateAction<VideoSegment | null>>;
    setSelectedVideo: React.Dispatch<React.SetStateAction<string>>;
}

export function useB3hdMode({
    videoB3hdMode,
    inputSource,
    videoList,
    b3hdSegmentLength,
    b3hdIntervalSeconds,
    setCurrentSegment,
    setSelectedVideo,
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

        playNextSegment();

        return () => {
            if (b3hdTimerRef.current) {
                clearTimeout(b3hdTimerRef.current);
                b3hdTimerRef.current = null;
            }
        };
    }, [videoB3hdMode, inputSource, b3hdSegmentLength, b3hdIntervalSeconds, videoList.length, setCurrentSegment, setSelectedVideo]);
}
