type AudioSourceType = 'mic' | 'element';

let sharedContext: AudioContext | null = null;
let currentSourceType: AudioSourceType | null = null;
let sourceNode: MediaStreamAudioSourceNode | MediaElementAudioSourceNode | null = null;
let lowpassNode: BiquadFilterNode | null = null;
let analyserNode: AnalyserNode | null = null;
let mediaStream: MediaStream | null = null;
let mediaElement: HTMLMediaElement | null = null;

function detachCurrentGraph() {
  sourceNode?.disconnect();
  lowpassNode?.disconnect();
  analyserNode?.disconnect();
  sourceNode = null;
  lowpassNode = null;
  analyserNode = null;
  currentSourceType = null;
}

export async function getSharedAudioContext(): Promise<AudioContext> {
  if (!sharedContext) {
    sharedContext = new AudioContext();
  }
  if (sharedContext.state === 'suspended') {
    await sharedContext.resume();
  }
  return sharedContext;
}

export async function connectSource(
  source: AudioSourceType,
  el?: HTMLMediaElement
): Promise<AnalyserNode> {
  const context = await getSharedAudioContext();
  if (analyserNode && currentSourceType === source) {
    if (source === 'element' && el && mediaElement === el) {
      return analyserNode;
    }
    if (source === 'mic') {
      return analyserNode;
    }
  }

  await disposeAudioGraph();

  if (source === 'mic') {
    mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    sourceNode = context.createMediaStreamSource(mediaStream);
  } else {
    if (!el) {
      throw new Error('HTMLMediaElement is required for element audio source.');
    }
    mediaElement = el;
    sourceNode = context.createMediaElementSource(el);
  }

  lowpassNode = context.createBiquadFilter();
  lowpassNode.type = 'lowpass';
  lowpassNode.frequency.value = 120;
  lowpassNode.Q.value = 0.707;

  analyserNode = context.createAnalyser();
  analyserNode.fftSize = 1024;
  analyserNode.smoothingTimeConstant = 0.6;

  sourceNode.connect(lowpassNode);
  lowpassNode.connect(analyserNode);
  currentSourceType = source;
  return analyserNode;
}

export async function disposeAudioGraph(): Promise<void> {
  detachCurrentGraph();
  if (mediaStream) {
    for (const track of mediaStream.getTracks()) {
      track.stop();
    }
    mediaStream = null;
  }
  mediaElement = null;
}

