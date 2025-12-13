import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import { Renderer } from './renderer/Renderer';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource } from './renderer/types';
import { pipeline, env } from '@xenova/transformers';
import './style.css';

env.allowLocalModels = false;
// env.backends.onnx.executionProviders = ['webgpu'];
env.backends.onnx.logLevel = 'warning';
const model_loc = 'Xenova/dpt-hybrid-midas'

function App() {
  const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
  const [mode, setMode] = useState<RenderMode>('liquid');
  const [zoom, setZoom] = useState(1.0);
  const [panX, setPanX] = useState(0.5);
  const [panY, setPanY] = useState(0.5);
  const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
  const [autoChangeDelay, setAutoChangeDelay] = useState(10);
  const [status, setStatus] = useState('Ready. Click "Load AI Model" for depth effects.');
  const [depthEstimator, setDepthEstimator] = useState<any>(null);
  const [depthMapResult, setDepthMapResult] = useState<any>(null);
  const [farthestPoint, setFarthestPoint] = useState({ x: 0.5, y: 0.5 });
  const [mousePosition, setMousePosition] = useState({ x: -1, y: -1 });
  const [isMouseDown, setIsMouseDown] = useState(false);
  const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);

  // Infinite Zoom Parameters
  const [lightStrength, setLightStrength] = useState(1.0);
  const [ambient, setAmbient] = useState(0.2);
  const [normalStrength, setNormalStrength] = useState(0.1);
  const [fogFalloff, setFogFalloff] = useState(4.0);
  const [depthThreshold, setDepthThreshold] = useState(0.5);

  // Generic Params (Rain, etc.)
  const [zoomParam1, setZoomParam1] = useState(0.5);
  const [zoomParam2, setZoomParam2] = useState(0.5);
  const [zoomParam3, setZoomParam3] = useState(0.5);
  const [zoomParam4, setZoomParam4] = useState(0.5);

  // Video Input State
  const [inputSource, setInputSource] = useState<InputSource>('image');
  const [videoList, setVideoList] = useState<string[]>([]);
  const [selectedVideo, setSelectedVideo] = useState<string>('');
  const [isMuted, setIsMuted] = useState(true);

  const rendererRef = useRef<Renderer | null>(null);
  const debugCanvasRef = useRef<HTMLCanvasElement>(null);

  const loadModel = async () => {
        if (depthEstimator) { setStatus('Model already loaded.'); return; }
        try {
            setStatus('Loading model...');
            const estimator = await pipeline('depth-estimation', model_loc, {
                 progress_callback: (progress: any) => {
                    if (progress.status === 'progress' && typeof progress.progress === 'number') {
                        setStatus(`Loading model... ${progress.progress.toFixed(2)}%`);
                    } else {
                        setStatus(progress.status);
                    }
                },
            quantized: false // Correct: Use this to load the FP32 model
            });
            setDepthEstimator(() => estimator);
            setStatus('Model Loaded. Processing initial image...');
        } catch (e: any) {
            console.error(e);
            setStatus(`Failed to load model: ${e.message}`);
        }
    };

  const runDepthAnalysis = useCallback(async (imageUrl: string) => {
      if (!depthEstimator || !rendererRef.current) return;
      setStatus('Analyzing image with AI model...');
      try {
          const result = await depthEstimator(imageUrl);
          const { data, dims } = result.predicted_depth;
          const [height, width] = [dims[dims.length - 2], dims[dims.length - 1]];

          let min = Infinity, max = -Infinity;
          let minIndex = 0;
          data.forEach((v: number, i: number) => {
              if (v < min) {
                  min = v;
                  minIndex = i;
              }
              if (v > max) max = v;
          });

          const farthestY = Math.floor(minIndex / width);
          const farthestX = minIndex % width;
          setFarthestPoint({ x: farthestX / width, y: farthestY / height });

          const range = max - min;
          const normalizedData = new Float32Array(data.length);

          for (let i = 0; i < data.length; ++i) {
              normalizedData[i] = 1.0 - ((data[i] - min) / range);
          }

          setStatus('Updating depth map on GPU...');
          rendererRef.current.updateDepthMap(normalizedData, width, height);

          setDepthMapResult(result);
          setStatus('Ready.');
      } catch (e: any) {
          console.error("Error during analysis:", e);
          setStatus(`Failed to analyze image: ${e.message}`);
      }
  }, [depthEstimator]);

  const handleNewImage = useCallback(async () => {
      if (!rendererRef.current) {
          console.warn("Renderer not ready yet.");
          return;
      }
      setStatus('Loading random image...');
      const newImageUrl = await rendererRef.current.loadRandomImage();

      if (newImageUrl) {
          if (depthEstimator) {
              await runDepthAnalysis(newImageUrl);
          } else {
              setFarthestPoint({ x: 0.5, y: 0.5 });
              setStatus('Ready. Load AI model to add depth effects.');
          }
      } else {
          setStatus('Failed to load a random image.');
      }
  }, [depthEstimator, runDepthAnalysis]);

  useEffect(() => {
      let intervalId: NodeJS.Timeout | null = null;
      if (autoChangeEnabled && inputSource === 'image') {
          intervalId = setInterval(handleNewImage, autoChangeDelay * 1000);
      }
      return () => { if (intervalId) clearInterval(intervalId); };
  }, [autoChangeEnabled, autoChangeDelay, handleNewImage, inputSource]);

  useEffect(() => {
      if (depthMapResult?.predicted_depth && debugCanvasRef.current) {
          const { data, dims } = depthMapResult.predicted_depth;
          const [height, width] = [dims[dims.length - 2], dims[dims.length - 1]];
          const canvas = debugCanvasRef.current;
          const context = canvas.getContext('2d');
          if (!width || !height || !context) return;

          canvas.width = width;
          canvas.height = height;
          const imageData = context.createImageData(width, height);

          let min = Infinity, max = -Infinity;
          data.forEach((v: number) => {
              if (v < min) min = v;
              if (v > max) max = v;
          });
          const range = max - min;
          for (let i = 0; i < data.length; ++i) {
              const value = Math.round(((data[i] - min) / range) * 255);
              imageData.data[i * 4 + 0] = value;
              imageData.data[i * 4 + 1] = value;
              imageData.data[i * 4 + 2] = value;
              imageData.data[i * 4 + 3] = 255;
          }
          context.putImageData(imageData, 0, 0);
      }
  }, [depthMapResult]);

  const handleInit = useCallback(() => {
    if (rendererRef.current) {
        setAvailableModes(rendererRef.current.getAvailableModes());
        // Initial sync of input source
        rendererRef.current.setInputSource(inputSource);
    }
  }, [inputSource]);

  // Sync input source when changed
  useEffect(() => {
      if (rendererRef.current) {
          rendererRef.current.setInputSource(inputSource);
      }
  }, [inputSource]);

  // Set default params for Rain mode
  useEffect(() => {
      if (mode === 'rain') {
          setZoomParam1(0.08); // Speed
          setZoomParam2(0.5);  // Density
          setZoomParam3(2.0);  // Wind
          setZoomParam4(0.7);  // Splash
      }
      if (mode === 'chromatic-manifold') {
          // manifoldScale, curvatureStr, hueWeight, feedbackStr
          setZoomParam1(0.5); // manifoldScale
          setZoomParam2(0.5); // curvature
          setZoomParam3(0.9); // hueWeight
          setZoomParam4(0.9); // feedback
      }
      if (mode === 'digital-decay') {
          setZoomParam1(0.5); // Decay Intensity
          setZoomParam2(0.5); // Block Size
          setZoomParam3(0.5); // Corruption Speed
          setZoomParam4(0.5); // Depth Focus
      }
      if (mode === 'spectral-vortex') {
          setZoomParam1(2.0); // Twist Strength
          setZoomParam2(0.02); // Distortion Step
          setZoomParam3(0.1); // Color Shift
          setZoomParam4(0.0); // Unused
      }
      if (mode === 'quantum-fractal') {
          setZoomParam1(3.0); // Scale
          setZoomParam2(100.0); // Iterations
          setZoomParam3(1.0); // Entanglement
          setZoomParam4(0.0); // Unused
      }
      if (mode === 'magnetic-field') {
          setZoomParam1(0.5); // Strength
          setZoomParam2(0.5); // Radius
          setZoomParam3(0.2); // Density
          setZoomParam4(0.0); // Mode (Attract)
      }
      if (mode === 'pixel-sorter') {
          setZoomParam1(0.0); // Direction (Vertical)
          setZoomParam2(0.0); // Reverse (Off)
          setZoomParam3(0.0); // Unused
          setZoomParam4(0.0); // Unused
      }
  }, [mode]);

  // Fetch video list
  useEffect(() => {
      const fetchVideos = async () => {
          try {
              // Try to list files in public/videos
              // Note: This relies on server directory listing which might be disabled.
              // If so, we might need a manual list or a server endpoint.
              // For now, let's try to fetch the index page of /videos/
              const response = await fetch('videos/');
              if (response.ok) {
                  const text = await response.text();
                  // Parse HTML to find links
                  const parser = new DOMParser();
                  const doc = parser.parseFromString(text, 'text/html');
                  const links = Array.from(doc.querySelectorAll('a'));
                  const videos = links
                      .map(link => link.getAttribute('href'))
                      .filter(href => href && /\.(mp4|webm|mov)$/i.test(href))
                      .map(href => {
                          // Clean up href: remove leading /videos/ if present or just take the filename
                          const parts = href!.split('/');
                          return parts[parts.length - 1];
                      });

                  // Filter valid unique names
                  const uniqueVideos = Array.from(new Set(videos));
                  if (uniqueVideos.length > 0) {
                      setVideoList(uniqueVideos as string[]);
                      if (!selectedVideo) setSelectedVideo(uniqueVideos[0]);
                  }
              }
          } catch (e) {
              console.error("Failed to fetch video list", e);
          }
      };

      fetchVideos();
  }, []); // Run once

  return (
    <div id="app-container">
        <h1>WebGPU Liquid + Depth Effect</h1>
        <p><strong>Status:</strong> {status}</p>
        <Controls
            mode={mode}
            setMode={setMode}
            shaderCategory={shaderCategory}
            setShaderCategory={setShaderCategory}
            zoom={zoom} setZoom={setZoom}
            panX={panX} setPanX={setPanX}
            panY={panY} setPanY={setPanY}
            onNewImage={handleNewImage}
            autoChangeEnabled={autoChangeEnabled}
            setAutoChangeEnabled={setAutoChangeEnabled}
            autoChangeDelay={autoChangeDelay}
            setAutoChangeDelay={setAutoChangeDelay}
            onLoadModel={loadModel}
            isModelLoaded={!!depthEstimator}
            availableModes={availableModes}
            // New Props
            inputSource={inputSource}
            setInputSource={setInputSource}
            videoList={videoList}
            selectedVideo={selectedVideo}
            setSelectedVideo={setSelectedVideo}
            isMuted={isMuted}
            setIsMuted={setIsMuted}
            // Infinite Zoom
            lightStrength={lightStrength} setLightStrength={setLightStrength}
            ambient={ambient} setAmbient={setAmbient}
            normalStrength={normalStrength} setNormalStrength={setNormalStrength}
            fogFalloff={fogFalloff} setFogFalloff={setFogFalloff}
            depthThreshold={depthThreshold} setDepthThreshold={setDepthThreshold}
            // Generic Params
            zoomParam1={zoomParam1} setZoomParam1={setZoomParam1}
            zoomParam2={zoomParam2} setZoomParam2={setZoomParam2}
            zoomParam3={zoomParam3} setZoomParam3={setZoomParam3}
            zoomParam4={zoomParam4} setZoomParam4={setZoomParam4}
        />
        <WebGPUCanvas
            rendererRef={rendererRef}
            mode={mode}
            // Infinite Zoom
            lightStrength={lightStrength}
            ambient={ambient}
            normalStrength={normalStrength}
            fogFalloff={fogFalloff}
            depthThreshold={depthThreshold}
            // Generic Params
            zoomParam1={zoomParam1}
            zoomParam2={zoomParam2}
            zoomParam3={zoomParam3}
            zoomParam4={zoomParam4}
            zoom={zoom}
            panX={panX}
            panY={panY}
            farthestPoint={farthestPoint}
            mousePosition={mousePosition}
            setMousePosition={setMousePosition}
            isMouseDown={isMouseDown}
            setIsMouseDown={setIsMouseDown}
            onInit={handleInit}
            // New Props
            inputSource={inputSource}
            selectedVideo={selectedVideo}
            isMuted={isMuted}
        />
        {depthMapResult && (
            <div className="debug-container">
                <h2>AI Model Output (Debug Depth Map)</h2>
                <canvas ref={debugCanvasRef} style={{ maxWidth: '100%', height: 'auto', border: '1px solid grey' }} />
            </div>
        )}
    </div>
);
}

export default App;
