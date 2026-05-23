import { useRef, useCallback, useEffect, useState } from 'react';

interface AudioData {
  bass: number;
  mid: number;
  treble: number;
  overall: number;
}

/** Number of FFT frequency bins exposed to shaders via extraBuffer[5..132]. */
export const AUDIO_FFT_BINS = 128;

export const useAudioAnalyzer = () => {
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const dataArrayRef = useRef<Uint8Array | null>(null);
  // Reusable Float32Array for bin data to avoid per-frame allocations
  const binsRef = useRef<Float32Array>(new Float32Array(AUDIO_FFT_BINS));
  const [isActive, setIsActive] = useState(false);

  const startAudio = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

      audioContextRef.current = new AudioContext();
      analyserRef.current = audioContextRef.current.createAnalyser();
      // fftSize=256 → frequencyBinCount=128, matching AUDIO_FFT_BINS
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

  /**
   * Returns the raw 128-bin FFT magnitude array (values normalised to [0, 1]).
   * The returned Float32Array is reused each frame — copy it if you need to
   * keep it beyond the current frame.
   *
   * These bins map directly to extraBuffer[5..132] in shaders:
   *   bin 0  → extraBuffer[5]  (lowest frequency, ~86 Hz at 44.1 kHz / fftSize=256)
   *   bin 127 → extraBuffer[132] (highest bin, ~22 kHz)
   */
  const getAudioBins = useCallback((): Float32Array => {
    const analyser = analyserRef.current;
    const dataArray = dataArrayRef.current;
    const bins = binsRef.current;

    if (!analyser || !dataArray) {
      bins.fill(0);
      return bins;
    }

    // Re-use the same Uint8Array populated by getAudioData if already called
    // this frame; otherwise fetch fresh data.
    analyser.getByteFrequencyData(dataArray);

    const len = Math.min(dataArray.length, AUDIO_FFT_BINS);
    for (let i = 0; i < len; i++) {
      bins[i] = dataArray[i] / 255;
    }
    // Zero any remaining slots if bin count < AUDIO_FFT_BINS
    for (let i = len; i < AUDIO_FFT_BINS; i++) {
      bins[i] = 0;
    }

    return bins;
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
    getAudioBins,
    isActive,
  };
};

export default useAudioAnalyzer;
