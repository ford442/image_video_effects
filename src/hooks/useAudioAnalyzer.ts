import { useRef, useCallback, useEffect, useState } from 'react';

interface AudioData {
  bass: number;
  mid: number;
  treble: number;
  overall: number;
}

export const useAudioAnalyzer = () => {
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const dataArrayRef = useRef<Uint8Array | null>(null);
  const [isActive, setIsActive] = useState(false);

  const startAudio = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
      audioContextRef.current = new AudioContext();
      analyserRef.current = audioContextRef.current.createAnalyser();
      analyserRef.current.fftSize = 256;
      
      sourceRef.current = audioContextRef.current.createMediaStreamSource(stream);
      sourceRef.current.connect(analyserRef.current);
      
      const bufferLength = analyserRef.current.frequencyBinCount;
      dataArrayRef.current = new Uint8Array(bufferLength);
      
      setIsActive(true);
      console.log('✅ Audio analyzer started');
    } catch (err) {
      console.error('❌ Audio access denied:', err);
    }
  }, []);

  const stopAudio = useCallback(() => {
    sourceRef.current?.disconnect();
    audioContextRef.current?.close();
    setIsActive(false);
  }, []);

  const getAudioData = useCallback((): AudioData => {
    const analyser = analyserRef.current;
    const dataArray = dataArrayRef.current;
    
    if (!analyser || !dataArray) {
      return { bass: 0, mid: 0, treble: 0, overall: 0 };
    }

    analyser.getByteFrequencyData(dataArray);
    
    const bufferLength = dataArray.length;
    const bassEnd = Math.floor(bufferLength * 0.1);
    const midEnd = Math.floor(bufferLength * 0.5);
    
    let bass = 0, mid = 0, treble = 0, overall = 0;
    
    for (let i = 0; i < bufferLength; i++) {
      const value = dataArray[i] / 255;
      overall += value;
      
      if (i < bassEnd) {
        bass += value;
      } else if (i < midEnd) {
        mid += value;
      } else {
        treble += value;
      }
    }
    
    bass /= bassEnd || 1;
    mid /= (midEnd - bassEnd) || 1;
    treble /= (bufferLength - midEnd) || 1;
    overall /= bufferLength;
    
    return { bass, mid, treble, overall };
  }, []);

  useEffect(() => {
    return () => {
      stopAudio();
    };
  }, [stopAudio]);

  return {
    startAudio,
    stopAudio,
    getAudioData,
    isActive,
  };
};

export default useAudioAnalyzer;
