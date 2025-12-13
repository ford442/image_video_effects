import {RenderMode, ShaderEntry, InputSource} from './types';

export class Renderer {
    private canvas: HTMLCanvasElement;
    private device!: GPUDevice;
    private context!: GPUCanvasContext;
    private presentationFormat!: GPUTextureFormat;
    private pipelines = new Map<string, GPURenderPipeline | GPUComputePipeline>();
    private bindGroups = new Map<string, GPUBindGroup>();
    private filteringSampler!: GPUSampler;
    private nonFilteringSampler!: GPUSampler;
    private comparisonSampler!: GPUSampler;
    private imageUrls: string[] = [];
    private ripplePoints: { x: number, y: number, startTime: number }[] = [];
    private MAX_RIPPLES = 100;
    private computeUniformBuffer!: GPUBuffer;
    private imageVideoUniformBuffer!: GPUBuffer;
    private galaxyUniformBuffer!: GPUBuffer;
    private videoTexture!: GPUTexture;
    private imageTexture!: GPUTexture;
    private writeTexture!: GPUTexture;
    private depthTextureRead!: GPUTexture;
    private depthTextureWrite!: GPUTexture;
    private dataTextureA!: GPUTexture;
    private dataTextureB!: GPUTexture;
    private dataTextureC!: GPUTexture;
    private extraBuffer!: GPUBuffer;
    private fgSpeed: number = 0.08;
    private bgSpeed: number = 0.0;
    private parallaxStrength: number = 2.0;
    private fogDensity: number = 0.7;
    // Infinite Zoom Parameters
    private lightStrength: number = 1.0;
    private ambient: number = 0.2;
    private normalStrength: number = 0.1;
    private fogFalloff: number = 4.0;
    private depthThreshold: number = 0.5;

    private shaderList: ShaderEntry[] = [];
    private inputSource: InputSource = 'image';

    // Plasma Mode State
    private plasmaBalls: {
        x: number, y: number, vx: number, vy: number,
        r: number, g: number, b: number, radius: number,
        age: number, maxAge: number, seed: number
    }[] = [];
    private plasmaBuffer!: GPUBuffer;
    private MAX_PLASMA_BALLS = 50;

    constructor(canvas: HTMLCanvasElement) {
        this.canvas = canvas;
    }

    public getAvailableModes(): ShaderEntry[] {
        return this.shaderList;
    }

    public setInputSource(source: InputSource) {
        this.inputSource = source;
        this.createBindGroups();
    }

    public addRipplePoint(x: number, y: number) {
        this.ripplePoints.push({x, y, startTime: performance.now() / 1000.0});
    }

    public firePlasma(x: number, y: number, vx: number, vy: number) {
        if (this.plasmaBalls.length >= this.MAX_PLASMA_BALLS) return;

        // Random colors (fire/plasma palette: red, orange, yellow, sometimes blue/purple)
        // Let's do a mix.
        const r = 0.8 + Math.random() * 0.2;
        const g = Math.random() * 0.6;
        const b = Math.random() * 0.2;

        this.plasmaBalls.push({
            x, y, vx, vy,
            r, g, b,
            radius: 0.05 + Math.random() * 0.08, // Bigger Base radius (0.05 - 0.13)
            age: 0,
            maxAge: 5.0 + Math.random() * 5.0, // Lives for 5-10 seconds
            seed: Math.random() * 100.0
        });
    }

    private updatePlasma(dt: number) {
        // 1. Update positions and age
        for (let i = this.plasmaBalls.length - 1; i >= 0; i--) {
            const ball = this.plasmaBalls[i];
            ball.x += ball.vx * dt;
            ball.y += ball.vy * dt;
            ball.age += dt;

            // Gravity? Maybe slight gravity or just drag?
            // "Strands or wisps" might imply some drag.
            ball.vx *= 0.99;
            ball.vy *= 0.99;

            if (ball.age > ball.maxAge ||
                ball.x < -0.5 || ball.x > 1.5 ||
                ball.y < -0.5 || ball.y > 1.5) {
                // Remove if too old or far off screen
                this.plasmaBalls.splice(i, 1);
            }
        }

        // 2. Collisions (Ball vs Ball)
        for (let i = 0; i < this.plasmaBalls.length; i++) {
            for (let j = i + 1; j < this.plasmaBalls.length; j++) {
                const b1 = this.plasmaBalls[i];
                const b2 = this.plasmaBalls[j];

                const dx = b2.x - b1.x;
                const dy = b2.y - b1.y;
                const dist = Math.sqrt(dx*dx + dy*dy);
                const minDist = b1.radius + b2.radius;

                if (dist < minDist && dist > 0.0001) {
                    // Elastic collision approximation
                    // Normalize normal vector
                    const nx = dx / dist;
                    const ny = dy / dist;

                    // Relative velocity
                    const dvx = b1.vx - b2.vx;
                    const dvy = b1.vy - b2.vy;

                    // Speed along normal
                    const normalVel = dvx * nx + dvy * ny;

                    // If moving away, ignore
                    if (normalVel < 0) continue;

                    // Impulse (assume equal mass for simplicity)
                    // j = -(1 + e) * v_rel_norm / (1/m1 + 1/m2)
                    // e = 1 (elastic)
                    // m1=m2=1
                    // j = -2 * normalVel / 2 = -normalVel

                    const impulse = -normalVel; // restitution 1.0

                    b1.vx += impulse * nx;
                    b1.vy += impulse * ny;
                    b2.vx -= impulse * nx;
                    b2.vy -= impulse * ny;

                    // Separate to prevent sticking
                    const overlap = minDist - dist;
                    const separationX = nx * overlap * 0.5;
                    const separationY = ny * overlap * 0.5;
                    b1.x -= separationX;
                    b1.y -= separationY;
                    b2.x += separationX;
                    b2.y += separationY;
                }
            }
        }
    }

    public updateZoomParams(params: {
        fgSpeed?: number,
        bgSpeed?: number,
        parallaxStrength?: number,
        fogDensity?: number
    }): void {
        if (params.fgSpeed !== undefined) this.fgSpeed = params.fgSpeed;
        if (params.bgSpeed !== undefined) this.bgSpeed = params.bgSpeed;
        if (params.parallaxStrength !== undefined) this.parallaxStrength = params.parallaxStrength;
        if (params.fogDensity !== undefined) this.fogDensity = params.fogDensity;
    }

    public updateLightingParams(params: {
        lightStrength?: number,
        ambient?: number,
        normalStrength?: number,
        fogFalloff?: number,
        depthThreshold?: number
    }): void {
        if (params.lightStrength !== undefined) this.lightStrength = params.lightStrength;
        if (params.ambient !== undefined) this.ambient = params.ambient;
        if (params.normalStrength !== undefined) this.normalStrength = params.normalStrength;
        if (params.fogFalloff !== undefined) this.fogFalloff = params.fogFalloff;
        if (params.depthThreshold !== undefined) this.depthThreshold = params.depthThreshold;
    }

    public destroy(): void {
        if (this.imageTexture) this.imageTexture.destroy();
        if (this.videoTexture) this.videoTexture.destroy();
        if (this.depthTextureRead) this.depthTextureRead.destroy();
        if (this.depthTextureWrite) this.depthTextureWrite.destroy();
        if (this.dataTextureA) this.dataTextureA.destroy();
        if (this.dataTextureB) this.dataTextureB.destroy();
        if (this.dataTextureC) this.dataTextureC.destroy();
        if (this.writeTexture) this.writeTexture.destroy();
        if (this.device) this.device.destroy();
    }

    public async init(): Promise<boolean> {
        if (!navigator.gpu) return false;
        const adapter = await navigator.gpu.requestAdapter();
        if (!adapter) return false;
        const requiredFeatures: GPUFeatureName[] = [];
        if (adapter.features.has('float32-filterable')) {
            requiredFeatures.push('float32-filterable');
        } else {
            console.log("Device does not support 'float32-filterable', using two-sampler workaround.");
        }
        this.device = await adapter.requestDevice({
            requiredFeatures,
        });
        this.context = this.canvas.getContext('webgpu')!;
        this.presentationFormat = navigator.gpu.getPreferredCanvasFormat();
        this.context.configure({device: this.device, colorSpace: "display-p3", format: this.presentationFormat, alphaMode: 'premultiplied', toneMapping: {mode: "extended"}});
        await this.fetchImageUrls();
        await this.fetchShaderList();
        await this.createResources();
        await this.createPipelines();
        await this.loadRandomImage();
        return true;
    }

    private async fetchShaderList(): Promise<void> {
        try {
            const response = await fetch('shader-list.json');
            if (!response.ok) throw new Error(`Failed to load shader list: ${response.status}`);
            this.shaderList = await response.json();
        } catch (e) {
            console.error("Failed to fetch shader list:", e);
            this.shaderList = [];
        }
    }

    private async fetchImageUrls(): Promise<void> {
        const bucketName = 'my-sd35-space-images-2025';
        const apiUrl = `https://storage.googleapis.com/storage/v1/b/${bucketName}/o`;
        try {
            const response = await fetch(apiUrl);
            if (!response.ok) throw new Error(`API error: ${response.status}`);
            const data = await response.json();
            this.imageUrls = data.items ? data.items.map((item: {
                name: string
            }) => `https://storage.googleapis.com/${bucketName}/${item.name}`) : [];
        } catch (e) {
            console.error("Failed to fetch image list:", e);
            this.imageUrls = ['https://i.imgur.com/vCNL2sT.jpeg'];
        }
    }

    public async loadRandomImage(): Promise<string | undefined> {
        try {
            if (this.imageUrls.length === 0) return;
            const imageUrl = this.imageUrls[Math.floor(Math.random() * this.imageUrls.length)];
            const response = await fetch(imageUrl);
            const imageBitmap = await createImageBitmap(await response.blob());
            if (this.imageTexture) this.imageTexture.destroy();
            this.imageTexture = this.device.createTexture({
                size: [imageBitmap.width, imageBitmap.height],
                format: 'rgba32float',
                usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
            });
            this.device.queue.copyExternalImageToTexture({source: imageBitmap}, {texture: this.imageTexture, colorSpace:"display-p3"}, [imageBitmap.width, imageBitmap.height]);
            this.createBindGroups();
            return imageUrl;
        } catch (e) {
            console.error("Failed to load image:", e);
            return undefined;
        }
    }

    public updateDepthMap(data: Float32Array, width: number, height: number): void {
        if (!this.device) return;
        if (this.depthTextureRead && (this.depthTextureRead.width !== width || this.depthTextureRead.height !== height)) {
            this.depthTextureRead.destroy();
            this.depthTextureWrite.destroy();
        }
        if (!this.depthTextureRead || this.depthTextureRead.width !== width || this.depthTextureRead.height !== height) {
            const depthTextureDescriptor: GPUTextureDescriptor = {
                size: [width, height],
                format: 'r32float',
                usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.STORAGE_BINDING,
            };
            this.depthTextureRead = this.device.createTexture(depthTextureDescriptor);
            this.depthTextureWrite = this.device.createTexture(depthTextureDescriptor);
        }
        this.device.queue.writeTexture({texture: this.depthTextureRead}, data, {
            bytesPerRow: width * 4,
            rowsPerImage: height
        }, [width, height]);
        this.device.queue.writeTexture({texture: this.depthTextureWrite}, data, {
            bytesPerRow: width * 4,
            rowsPerImage: height
        }, [width, height]);
        this.createBindGroups();
    }

    private async createResources(): Promise<void> {
        const {width, height} = this.canvas;
        this.filteringSampler = this.device.createSampler({
            magFilter: 'linear',
            minFilter: 'linear',
            addressModeU: 'repeat',
            addressModeV: 'repeat',
        });
        this.nonFilteringSampler = this.device.createSampler({
            magFilter: 'nearest',
            minFilter: 'nearest',
            addressModeU: 'repeat',
            addressModeV: 'repeat',
        });
        this.comparisonSampler = this.device.createSampler({
            compare: 'less',
        });
        this.galaxyUniformBuffer = this.device.createBuffer({
            size: 16,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
        });
        this.imageVideoUniformBuffer = this.device.createBuffer({
            size: 32 + (this.MAX_RIPPLES * 16),
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
        });
        this.computeUniformBuffer = this.device.createBuffer({
            size: 48 + (this.MAX_RIPPLES * 16),
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
        });
        const placeholderDepthDescriptor: GPUTextureDescriptor = {
            size: [1, 1],
            format: 'r32float',
            usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.STORAGE_BINDING,
        };
        this.depthTextureRead = this.device.createTexture(placeholderDepthDescriptor);
        this.depthTextureWrite = this.device.createTexture(placeholderDepthDescriptor);
        this.device.queue.writeTexture({texture: this.depthTextureRead}, new Float32Array([0.0]), {bytesPerRow: 4}, [1, 1]);
        this.device.queue.writeTexture({texture: this.depthTextureWrite}, new Float32Array([0.0]), {bytesPerRow: 4}, [1, 1]);
        this.writeTexture = this.device.createTexture({
            size: [width, height],
            format: 'rgba32float',
            usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
        });
        const dataStorageTextureDescriptor: GPUTextureDescriptor = {
            size: [width, height],
            format: 'rgba32float',
            usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.STORAGE_BINDING,
        };
        const dataTextureDescriptor: GPUTextureDescriptor = {
            size: [width, height],
            format: 'rgba32float',
            usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
        };
        this.dataTextureA = this.device.createTexture(dataStorageTextureDescriptor);
        this.dataTextureB = this.device.createTexture(dataStorageTextureDescriptor);
        this.dataTextureC = this.device.createTexture(dataTextureDescriptor);
        const initialExtraData = new Float32Array(256);
        this.extraBuffer = this.device.createBuffer({
            size: initialExtraData.byteLength,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC,
        });
        this.device.queue.writeBuffer(this.extraBuffer, 0, initialExtraData);

        this.plasmaBuffer = this.device.createBuffer({
            size: this.MAX_PLASMA_BALLS * 48, // 3 * vec4<f32> (16 bytes) = 48 bytes per ball
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        });
    }

    private async createPipelines(): Promise<void> {
        const commonConfig = {
            vertex: {module: null as any, entryPoint: 'vs_main'},
            fragment: {targets: [{format: this.presentationFormat}]},
            primitive: {topology: 'triangle-strip' as GPUPrimitiveTopology}
        };

        // 1. Static Render Pipelines
        const staticShaders = ['galaxy.wgsl', 'imageVideo.wgsl', 'texture.wgsl'];
        const staticCodes = await Promise.all(staticShaders.map(name => fetch(`shaders/${name}`).then(r => r.text())));
        const [galaxyCode, imageVideoCode, textureCode] = staticCodes;

        const galaxyModule = this.device.createShaderModule({code: galaxyCode});
        const imageVideoModule = this.device.createShaderModule({code: imageVideoCode});
        const textureModule = this.device.createShaderModule({code: textureCode});

        const galaxyPipeline = await this.device.createRenderPipelineAsync({
            layout: 'auto', ...commonConfig,
            vertex: {module: galaxyModule, entryPoint: 'vs_main'},
            fragment: {...commonConfig.fragment, module: galaxyModule, entryPoint: 'fs_main'},
            primitive: {topology: 'triangle-list' as GPUPrimitiveTopology}
        });
        this.pipelines.set('galaxy', galaxyPipeline);

        const imageVideoPipeline = await this.device.createRenderPipelineAsync({
            layout: 'auto', ...commonConfig,
            vertex: {module: imageVideoModule, entryPoint: 'vs_main'},
            fragment: {...commonConfig.fragment, module: imageVideoModule, entryPoint: 'fs_main'}
        });
        this.pipelines.set('imageVideo', imageVideoPipeline);

        const liquidRenderPipeline = await this.device.createRenderPipelineAsync({
            layout: 'auto', ...commonConfig,
            vertex: {module: textureModule, entryPoint: 'vs_main'},
            fragment: {...commonConfig.fragment, module: textureModule, entryPoint: 'fs_main'}
        });
        this.pipelines.set('liquid-render', liquidRenderPipeline);

        // 2. Dynamic Compute Pipelines
        const computeBindGroupLayout = this.device.createBindGroupLayout({
            entries: [
                { binding: 0, visibility: GPUShaderStage.COMPUTE, sampler: { type: 'filtering' as GPUSamplerBindingType } },
                { binding: 1, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'float' as GPUTextureSampleType } },
                { binding: 2, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only' as GPUStorageTextureAccess, format: 'rgba32float' as GPUTextureFormat } },
                { binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' as GPUBufferBindingType } },
                { binding: 4, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'float' as GPUTextureSampleType } },
                { binding: 5, visibility: GPUShaderStage.COMPUTE, sampler: { type: 'non-filtering' as GPUSamplerBindingType } },
                { binding: 6, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only' as GPUStorageTextureAccess, format: 'r32float' as GPUTextureFormat } },
                { binding: 7, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only' as GPUStorageTextureAccess, format: 'rgba32float' as GPUTextureFormat } },
                { binding: 8, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only' as GPUStorageTextureAccess, format: 'rgba32float' as GPUTextureFormat } },
                { binding: 9, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'float' as GPUTextureSampleType } },
                { binding: 10, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' as GPUBufferBindingType } },
                { binding: 11, visibility: GPUShaderStage.COMPUTE, sampler: { type: 'comparison' as GPUSamplerBindingType } },
                { binding: 12, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' as GPUBufferBindingType } },
            ],
        });

        const computePipelineLayout = this.device.createPipelineLayout({
            bindGroupLayouts: [computeBindGroupLayout],
        });

        for (const entry of this.shaderList) {
            try {
                const url = entry.url;
                const code = await fetch(url).then(r => r.text());
                const module = this.device.createShaderModule({code});

                const pipeline = await this.device.createComputePipelineAsync({
                    layout: computePipelineLayout,
                    compute: {module, entryPoint: 'main'}
                });
                this.pipelines.set(entry.id, pipeline);
            } catch (e) {
                console.error(`Failed to load shader ${entry.name} (${entry.url}):`, e);
            }
        }
    }

    private createBindGroups(): void {
        if (!this.imageTexture || !this.nonFilteringSampler || !this.comparisonSampler || !this.depthTextureRead || !this.depthTextureWrite || !this.dataTextureA|| !this.dataTextureB || !this.dataTextureC || !this.extraBuffer || !this.computeUniformBuffer || !this.plasmaBuffer) return;

        if (this.videoTexture) {
            this.bindGroups.set('galaxy', this.device.createBindGroup({
                layout: this.pipelines.get('galaxy')!.getBindGroupLayout(0),
                entries: [{binding: 0, resource: {buffer: this.galaxyUniformBuffer}}, {
                    binding: 1,
                    resource: this.filteringSampler
                }, {binding: 2, resource: this.videoTexture.createView()}]
            }));
            this.bindGroups.set('video', this.device.createBindGroup({
                layout: this.pipelines.get('imageVideo')!.getBindGroupLayout(0),
                entries: [{binding: 0, resource: this.filteringSampler}, {
                    binding: 1,
                    resource: this.videoTexture.createView()
                }, {binding: 2, resource: {buffer: this.imageVideoUniformBuffer}}]
            }));
        }
        this.bindGroups.set('image', this.device.createBindGroup({
            layout: this.pipelines.get('imageVideo')!.getBindGroupLayout(0),
            entries: [{binding: 0, resource: this.filteringSampler}, {
                binding: 1,
                resource: this.imageTexture.createView()
            }, {binding: 2, resource: {buffer: this.imageVideoUniformBuffer}}]
        }));
        this.bindGroups.set('liquid-render', this.device.createBindGroup({
            layout: this.pipelines.get('liquid-render')!.getBindGroupLayout(0),
            entries: [{binding: 0, resource: this.filteringSampler}, {
                binding: 1,
                resource: this.writeTexture.createView()
            }]
        }));

        // Get any compute pipeline to borrow its layout
        let computePipeline: GPUComputePipeline | undefined;
        for (const entry of this.shaderList) {
             const p = this.pipelines.get(entry.id);
             if (p) {
                 computePipeline = p as GPUComputePipeline;
                 break;
             }
        }

        if (!computePipeline) return;

        let inputTextureView = this.imageTexture.createView();
        if (this.inputSource === 'video' && this.videoTexture) {
            inputTextureView = this.videoTexture.createView();
        }

        const computeEntries = [
            {binding: 0, resource: this.filteringSampler},
            {binding: 1, resource: inputTextureView},
            {binding: 2, resource: this.writeTexture.createView()},
            {binding: 3, resource: {buffer: this.computeUniformBuffer}},
            {binding: 4, resource: this.depthTextureRead.createView()},
            {binding: 5, resource: this.nonFilteringSampler},
            {binding: 6, resource: this.depthTextureWrite.createView()},
            {binding: 7, resource: this.dataTextureA.createView()},
            {binding: 8, resource: this.dataTextureB.createView()},
            {binding: 9, resource: this.dataTextureC.createView()},
            {binding: 10, resource: {buffer: this.extraBuffer}},
            {binding: 11, resource: this.comparisonSampler},
            {binding: 12, resource: {buffer: this.plasmaBuffer}},
        ];

        const computeBindGroup = this.device.createBindGroup({
            layout: computePipeline.getBindGroupLayout(0),
            entries: computeEntries,
        });

        this.bindGroups.set('compute', computeBindGroup);
    }

    private swapDepthTextures() {
        const temp = this.depthTextureRead;
        this.depthTextureRead = this.depthTextureWrite;
        this.depthTextureWrite = temp;
    }

    public render(mode: RenderMode, videoElement: HTMLVideoElement, zoom: number, panX: number, panY: number, farthestPoint: {
        x: number,
        y: number
    }, mousePosition: { x: number, y: number }, isMouseDown: boolean): void {
        if (!this.device || !this.imageTexture) return;
        const currentTime = performance.now() / 1000.0;
        if (videoElement.readyState >= 2 && videoElement.videoWidth > 0) {
            if (!this.videoTexture || this.videoTexture.width !== videoElement.videoWidth || this.videoTexture.height !== videoElement.videoHeight) {
                if (this.videoTexture) this.videoTexture.destroy();
                this.videoTexture = this.device.createTexture({
                    size: [videoElement.videoWidth, videoElement.videoHeight],
                    format: 'rgba8unorm',
                    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT
                });
                this.createBindGroups();
            }
            this.device.queue.copyExternalImageToTexture({source: videoElement}, {texture: this.videoTexture}, [videoElement.videoWidth, videoElement.videoHeight]);
        }
        const commandEncoder = this.device.createCommandEncoder();

        // Check if mode is a compute shader
        const isComputeMode = this.shaderList.some(s => s.id === mode);

        if (isComputeMode) {
            // Plasma Physics Update
            if (mode === 'plasma') {
                // Calculate dt (roughly)
                // We don't have precise dt here, let's assume 60fps or measure it?
                // The render loop uses performance.now(), but we don't track lastFrameTime in class.
                // But render is called from animate() which runs at rAF.
                // Let's assume 16ms or use a static small step for stability.
                this.updatePlasma(0.016);

                // Write to Buffer
                const plasmaData = new Float32Array(this.MAX_PLASMA_BALLS * 12); // 12 floats per ball
                for (let i = 0; i < this.plasmaBalls.length; i++) {
                    const b = this.plasmaBalls[i];
                    const offset = i * 12;
                    // vec4 1: x, y, vx, vy
                    plasmaData[offset + 0] = b.x;
                    plasmaData[offset + 1] = b.y;
                    plasmaData[offset + 2] = b.vx;
                    plasmaData[offset + 3] = b.vy;
                    // vec4 2: r, g, b, radius
                    plasmaData[offset + 4] = b.r;
                    plasmaData[offset + 5] = b.g;
                    plasmaData[offset + 6] = b.b;
                    plasmaData[offset + 7] = b.radius;
                    // vec4 3: age, maxAge, seed, unused
                    plasmaData[offset + 8] = b.age;
                    plasmaData[offset + 9] = b.maxAge;
                    plasmaData[offset + 10] = b.seed;
                    plasmaData[offset + 11] = 0.0;
                }
                this.device.queue.writeBuffer(this.plasmaBuffer, 0, plasmaData);
            }

            const computePass = commandEncoder.beginComputePass();
            const computeBG = this.bindGroups.get('compute');

            if (computeBG) {
                const rippleLifetime = mode === 'liquid-viscous' ? 6.0 : 4.0; // Could make this dynamic later
                this.ripplePoints = this.ripplePoints.filter(p => (currentTime - p.startTime) < rippleLifetime);
                if (this.ripplePoints.length > this.MAX_RIPPLES) this.ripplePoints.splice(0, this.ripplePoints.length - this.MAX_RIPPLES);

                const rippleDataArr = new Float32Array(this.MAX_RIPPLES * 4);
                for (let i = 0; i < this.ripplePoints.length; i++) {
                    const point = this.ripplePoints[i];
                    rippleDataArr.set([point.x, point.y, point.startTime], i * 4);
                }

                const uniformArray = new Float32Array(12 + this.MAX_RIPPLES * 4);
                uniformArray.set([currentTime, this.ripplePoints.length, this.canvas.width, this.canvas.height], 0);

                // Infinite Zoom uses w for depthThreshold
                const zoomConfigW = mode === 'infinite-zoom' ? this.depthThreshold : 0;

                // For mouse-responsive shaders, inject mouse position instead of farthestPoint
                let zoomX = farthestPoint.x;
                let zoomY = farthestPoint.y;
                if (mode === 'cyber-lens' || mode === 'interactive-ripple' || mode === 'magnetic-field' || mode === 'pixel-sorter' || mode === 'cyber-ripples' || mode === 'cursor-aura') {
                    zoomX = mousePosition.x;
                    zoomY = mousePosition.y;
                }

                uniformArray.set([currentTime, zoomX, zoomY, zoomConfigW], 4);

                // For plasma mode, we might want to pass the number of active balls or other config
                // But we can just deduce it from the buffer (age > maxAge is dead)
                // or pass it in config.y (rippleCount) if we wanted, but here we are using ripplePoints for standard ripples.
                // Plasma balls are separate.

                const zoomParams = new Float32Array([
                    this.fgSpeed,
                    this.bgSpeed,
                    this.parallaxStrength,
                    this.fogDensity
                ]);
                uniformArray.set(zoomParams, 8);

                if (mode === 'infinite-zoom') {
                    // Overwrite ripples[0] with lighting params
                    const lightingParams = new Float32Array([
                        this.lightStrength,
                        this.ambient,
                        this.normalStrength,
                        this.fogFalloff
                    ]);
                    uniformArray.set(lightingParams, 12);
                } else {
                    uniformArray.set(rippleDataArr, 12);
                }

                this.device.queue.writeBuffer(this.computeUniformBuffer, 0, uniformArray);

                computePass.setBindGroup(0, computeBG);

                const pipeline = this.pipelines.get(mode) as GPUComputePipeline;
                if (pipeline) {
                    computePass.setPipeline(pipeline);
                    computePass.dispatchWorkgroups(Math.ceil(this.canvas.width / 8), Math.ceil(this.canvas.height / 8), 1);
                }
            }
            computePass.end();
            this.swapDepthTextures();
        }

        const textureView = this.context.getCurrentTexture().createView();
        const renderPassDescriptor: GPURenderPassDescriptor = {
            colorAttachments: [{
                view: textureView,
                clearValue: {r: 0.0, g: 0.0, b: 0.0, a: 1.0},
                loadOp: 'clear' as GPULoadOp,
                storeOp: 'store' as GPUStoreOp
            }]
        };
        const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);
        const liquidRenderPipeline = this.pipelines.get('liquid-render') as GPURenderPipeline;
        const imageVideoPipeline = this.pipelines.get('imageVideo') as GPURenderPipeline;
        const galaxyPipeline = this.pipelines.get('galaxy') as GPURenderPipeline;

        switch (mode) {
            case 'shader':
                if (galaxyPipeline && this.bindGroups.has('galaxy')) {
                    this.device.queue.writeBuffer(this.galaxyUniformBuffer, 0, new Float32Array([currentTime, zoom, panX, panY]));
                    passEncoder.setPipeline(galaxyPipeline);
                    passEncoder.setBindGroup(0, this.bindGroups.get('galaxy')!);
                    passEncoder.draw(6);
                }
                break;
            case 'image':
            case 'ripple':
                if (imageVideoPipeline && this.bindGroups.has('image')) {
                    const uniformArray = new Float32Array(8 + this.MAX_RIPPLES * 4);
                    uniformArray.set([this.canvas.width, this.canvas.height, this.imageTexture.width, this.imageTexture.height], 0);
                    uniformArray.set([currentTime, this.ripplePoints.length, mode === 'ripple' ? 1.0 : 0.0, 0.0], 4);
                    for (let i = 0; i < this.ripplePoints.length; i++) {
                        const point = this.ripplePoints[i];
                        uniformArray.set([point.x, point.y, point.startTime, 0.0], 8 + i * 4);
                    }
                    this.device.queue.writeBuffer(this.imageVideoUniformBuffer, 0, uniformArray);
                    passEncoder.setPipeline(imageVideoPipeline);
                    passEncoder.setBindGroup(0, this.bindGroups.get('image')!);
                    passEncoder.draw(4);
                }
                break;
            case 'video':
                if (imageVideoPipeline && this.bindGroups.has('video')) {
                    const uniformArray = new Float32Array(8);
                    uniformArray.set([this.canvas.width, this.canvas.height, this.videoTexture.width, this.videoTexture.height], 0);
                    uniformArray.set([currentTime, 0, 0, 0], 4);
                    this.device.queue.writeBuffer(this.imageVideoUniformBuffer, 0, uniformArray);
                    passEncoder.setPipeline(imageVideoPipeline);
                    passEncoder.setBindGroup(0, this.bindGroups.get('video')!);
                    passEncoder.draw(4);
                }
                break;
            default:
                // Assume generic compute shader rendering
                if (liquidRenderPipeline && this.bindGroups.has('liquid-render')) {
                    passEncoder.setPipeline(liquidRenderPipeline);
                    passEncoder.setBindGroup(0, this.bindGroups.get('liquid-render')!);
                    passEncoder.draw(4);
                }
                break;
        }
        passEncoder.end();
        this.device.queue.submit([commandEncoder.finish()]);
    }
}
