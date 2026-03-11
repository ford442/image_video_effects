import React, { useEffect, useRef, useState, useCallback } from 'react';

interface DanmakuMessage {
  id: string;
  text: string;
  x: number;
  y: number;
  speed: number;
  color: string;
  size: number;
  opacity: number;
}

interface DanmakuOverlayProps {
  enabled?: boolean;
  opacity?: number;
  density?: 'low' | 'medium' | 'high';
}

// Simulated danmaku messages
const SAMPLE_MESSAGES = [
  '666666', '太厉害了！', 'woc', '太强了', '这就是大佬吗',
  '主播操作可以的', '学到了', '已三连', '这是什么shader',
  'WebGPU牛逼', 'C++速度！', '这帧率爱了', ' Physarum 经典',
  '弹幕护体', '前方高能', '这效果太棒了', '怎么做到的',
  '代码开源吗', '求教程', '厉害了我的哥', '🔥🔥🔥',
];

export const DanmakuOverlay: React.FC<DanmakuOverlayProps> = ({
  enabled = true,
  opacity = 0.7,
  density = 'medium',
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const messagesRef = useRef<DanmakuMessage[]>([]);
  const animationRef = useRef<number>(0);
  const [dimensions, setDimensions] = useState({ width: 1920, height: 1080 });

  // Add a new danmaku message
  const addMessage = useCallback((text?: string) => {
    if (!enabled) return;

    const densityMultiplier = { low: 0.5, medium: 1, high: 2 }[density];
    if (Math.random() > 0.3 * densityMultiplier) return;

    const msg: DanmakuMessage = {
      id: Math.random().toString(36).substr(2, 9),
      text: text || SAMPLE_MESSAGES[Math.floor(Math.random() * SAMPLE_MESSAGES.length)],
      x: dimensions.width,
      y: Math.random() * (dimensions.height - 40) + 20,
      speed: 2 + Math.random() * 3,
      color: ['#fff', '#ff6b6b', '#4ecdc4', '#ffe66d', '#a8e6cf'][Math.floor(Math.random() * 5)],
      size: 16 + Math.random() * 8,
      opacity: opacity,
    };

    messagesRef.current.push(msg);
  }, [enabled, density, opacity, dimensions]);

  // Animation loop
  useEffect(() => {
    if (!enabled) return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Update canvas size
    canvas.width = dimensions.width;
    canvas.height = dimensions.height;

    const animate = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      // Add random messages
      if (Math.random() < 0.05) {
        addMessage();
      }

      // Update and draw messages
      messagesRef.current = messagesRef.current.filter(msg => {
        msg.x -= msg.speed;

        // Draw message
        ctx.font = `bold ${msg.size}px "Microsoft YaHei", sans-serif`;
        ctx.fillStyle = msg.color;
        ctx.globalAlpha = msg.opacity;
        ctx.strokeStyle = 'rgba(0,0,0,0.5)';
        ctx.lineWidth = 2;

        ctx.strokeText(msg.text, msg.x, msg.y);
        ctx.fillText(msg.text, msg.x, msg.y);
        ctx.globalAlpha = 1;

        // Keep if still visible
        return msg.x > -200;
      });

      animationRef.current = requestAnimationFrame(animate);
    };

    animate();

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [enabled, addMessage, dimensions]);

  if (!enabled) return null;

  return (
    <canvas
      ref={canvasRef}
      width={dimensions.width}
      height={dimensions.height}
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width: '100%',
        height: '100%',
        pointerEvents: 'none',
        zIndex: 10,
      }}
    />
  );
};

export default DanmakuOverlay;
