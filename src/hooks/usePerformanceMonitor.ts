import { useRef, useState, useCallback, useEffect } from 'react';

export interface PerformanceMetrics {
  fps: number;
  frameTime: number;
  frameCount: number;
}

export const usePerformanceMonitor = () => {
  const [fps, setFps] = useState(0);
  const [frameTime, setFrameTime] = useState(0);
  
  const rafRef = useRef<number | undefined>(undefined);
  const lastTimeRef = useRef<number>(0);
  const frameCountRef = useRef(0);
  const fpsUpdateRef = useRef(0);
  const runningRef = useRef(false);

  const measure = useCallback((timestamp: number) => {
    if (!runningRef.current) return;

    if (lastTimeRef.current > 0) {
      const delta = timestamp - lastTimeRef.current;
      frameCountRef.current++;

      // Update FPS every 500ms
      if (timestamp - fpsUpdateRef.current >= 500) {
        const fps = Math.round((frameCountRef.current * 1000) / (timestamp - fpsUpdateRef.current));
        setFps(fps);
        setFrameTime(delta);
        
        frameCountRef.current = 0;
        fpsUpdateRef.current = timestamp;
      }
    } else {
      fpsUpdateRef.current = timestamp;
    }

    lastTimeRef.current = timestamp;
    rafRef.current = requestAnimationFrame(measure);
  }, []);

  const startMonitoring = useCallback(() => {
    if (runningRef.current) return;
    runningRef.current = true;
    lastTimeRef.current = 0;
    frameCountRef.current = 0;
    fpsUpdateRef.current = 0;
    rafRef.current = requestAnimationFrame(measure);
  }, [measure]);

  const stopMonitoring = useCallback(() => {
    runningRef.current = false;
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
    }
  }, []);

  useEffect(() => {
    return () => {
      stopMonitoring();
    };
  }, [stopMonitoring]);

  return {
    fps,
    frameTime,
    startMonitoring,
    stopMonitoring,
  };
};

export default usePerformanceMonitor;
