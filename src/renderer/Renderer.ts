import {RenderMode, ShaderEntry, InputSource, SlotParams} from './types';

export class Renderer {
    private canvas: HTMLCanvasElement;
    private device!: GPUDevice;
    private context!: GPUCanvasContext;
    private presentationFormat!: GPUTextureFormat;
    private pipelines = new Map<string, GPURenderPipeline | GPUComputePipeline>();
    private bindGroups = new Map<string, GPUBindGroup>();
    private dynamicBindGroups = new Map<string, GPUBindGroup>(); // Cache for dynamic compute bindgroups
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

    // Intermediate textures for ping-pong
    private pingPongTexture1!: GPUTexture;
    private pingPongTexture2!: GPUTexture;

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

    // Helper to batch update params for legacy support or internal use
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
        if (this.pingPongTexture1) this.pingPongTexture1.destroy();
        if (this.pingPongTexture2) this.pingPongTexture2.destroy();
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

        const rwTextureDesc: GPUTextureDescriptor = {
            size: [width, height],
            format: 'rgba32float',
            usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
        };

        this.writeTexture = this.device.createTexture(rwTextureDesc);
        this.pingPongTexture1 = this.device.createTexture(rwTextureDesc);
        this.pingPongTexture2 = this.device.createTexture(rwTextureDesc);

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

        // Dynamic bindgroups are now created per-frame/per-pass as needed, clearing cache
        this.dynamicBindGroups.clear();
    }

    private getComputeBindGroup(pipeline: GPUComputePipeline, inputView: GPUTextureView, outputView: GPUTextureView): GPUBindGroup {
        // Create a unique key for this combination if we wanted to cache, but GPU objects don't have IDs readily available in JS without wrappers.
        // However, we can use a WeakMap or just recreate it if it's not too expensive.
        // For now, let's just create it. To optimize, we could cache based on texture object references if performance is an issue.
        // Actually, creating a bind group every frame is usually fine for this number of draw calls (3).

        return this.device.createBindGroup({
            layout: pipeline.getBindGroupLayout(0),
            entries: [
                {binding: 0, resource: this.filteringSampler},
                {binding: 1, resource: inputView},
                {binding: 2, resource: outputView},
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
            ],
        });
    }

    private swapDepthTextures() {
        const temp = this.depthTextureRead;
        this.depthTextureRead = this.depthTextureWrite;
        this.depthTextureWrite = temp;
    }

    public render(modes: RenderMode[], slotParams: SlotParams[], videoElement: HTMLVideoElement, zoom: number, panX: number, panY: number, farthestPoint: {
        x: number,
        y: number
    }, mousePosition: { x: number, y: number }, isMouseDown: boolean): void {
        if (!this.device || !this.imageTexture) return;
        const currentTime = performance.now() / 1000.0;

        // Handle Video Input
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

        // ---------------------------------------------------------
        // COMPUTE SHADER CHAIN
        // ---------------------------------------------------------

        // Determine input source texture
        let currentInputTexture = this.imageTexture;
        if (this.inputSource === 'video' && this.videoTexture) {
            currentInputTexture = this.videoTexture;
        }

        // We have 3 slots.
        // We need to determine the chain of execution.
        // Ping-ponging between pingPongTexture1 and pingPongTexture2.
        // Final result must end up in writeTexture.

        // Filter out 'none' modes
        const activeChain = modes.map((m, i) => ({ mode: m, params: slotParams[i] })).filter(item => {
             // Check if it's a valid compute shader
             return item.mode !== 'none' && this.shaderList.some(s => s.id === item.mode);
        });

        if (activeChain.length > 0) {
            // Plasma Update (Global Physics) - Run once if any plasma mode is present?
            // Or only if plasma is active?
            if (modes.includes('plasma')) {
                 this.updatePlasma(0.016);
                 const plasmaData = new Float32Array(this.MAX_PLASMA_BALLS * 12);
                 for (let i = 0; i < this.plasmaBalls.length; i++) {
                    const b = this.plasmaBalls[i];
                    const offset = i * 12;
                    plasmaData[offset + 0] = b.x; plasmaData[offset + 1] = b.y;
                    plasmaData[offset + 2] = b.vx; plasmaData[offset + 3] = b.vy;
                    plasmaData[offset + 4] = b.r; plasmaData[offset + 5] = b.g;
                    plasmaData[offset + 6] = b.b; plasmaData[offset + 7] = b.radius;
                    plasmaData[offset + 8] = b.age; plasmaData[offset + 9] = b.maxAge;
                    plasmaData[offset + 10] = b.seed; plasmaData[offset + 11] = 0.0;
                 }
                 this.device.queue.writeBuffer(this.plasmaBuffer, 0, plasmaData);
            }

            // Ripple Update (Shared state)
            const rippleLifetime = 4.0;
            this.ripplePoints = this.ripplePoints.filter(p => (currentTime - p.startTime) < rippleLifetime);
            if (this.ripplePoints.length > this.MAX_RIPPLES) this.ripplePoints.splice(0, this.ripplePoints.length - this.MAX_RIPPLES);
            const rippleDataArr = new Float32Array(this.MAX_RIPPLES * 4);
            for (let i = 0; i < this.ripplePoints.length; i++) {
                const point = this.ripplePoints[i];
                rippleDataArr.set([point.x, point.y, point.startTime], i * 4);
            }

            // Execute Chain
            for (let i = 0; i < activeChain.length; i++) {
                const { mode, params } = activeChain[i];
                const isLast = i === activeChain.length - 1;

                // Determine Output
                let targetTexture: GPUTexture;
                if (isLast) {
                    targetTexture = this.writeTexture;
                } else {
                    // Ping pong
                    targetTexture = (i % 2 === 0) ? this.pingPongTexture1 : this.pingPongTexture2;
                }

                // Update Uniforms for this pass
                const uniformArray = new Float32Array(12 + this.MAX_RIPPLES * 4);
                uniformArray.set([currentTime, this.ripplePoints.length, this.canvas.width, this.canvas.height], 0);

                // Note: zoomConfigW used to be depthThreshold for infinite-zoom.
                const zoomConfigW = mode === 'infinite-zoom' ? params.depthThreshold : 0;
                uniformArray.set([currentTime, farthestPoint.x, farthestPoint.y, zoomConfigW], 4);

                const zoomParamsArr = new Float32Array([
                    params.zoomParam1,
                    params.zoomParam2,
                    params.zoomParam3,
                    params.zoomParam4
                ]);
                uniformArray.set(zoomParamsArr, 8);

                if (mode === 'infinite-zoom') {
                    const lightingParams = new Float32Array([
                        params.lightStrength,
                        params.ambient,
                        params.normalStrength,
                        params.fogFalloff
                    ]);
                    uniformArray.set(lightingParams, 12);
                } else {
                    uniformArray.set(rippleDataArr, 12);
                }

                // We must queue write here. Note: If we have multiple passes, we must ensure ordering.
                // device.queue.writeBuffer happens on CPU timeline submit.
                // If we submit multiple writes to the same buffer in one frame, the LAST one wins for the whole command buffer unless we split submit.
                // THIS IS A CRITICAL WEBGPU DETAIL.
                // A single CommandEncoder recording multiple passes that use the SAME uniform buffer will see the SAME uniform values (the state at submission time)
                // UNLESS we use `writeBuffer` on the queue which schedules copy operations.
                // Wait, `queue.writeBuffer` schedules a write. If we call it multiple times, they are serialized.
                // But the draws/dispatches recorded in the command encoder will pick up the buffer state relative to the queue operations?
                // Actually, `queue.writeBuffer` operations are executed *before* any subsequently submitted command buffers.
                // But here we are building ONE command buffer.
                // So if we writeBuffer, then record pass 1, then writeBuffer, then record pass 2...
                // The `writeBuffer` is an async queue op. The command buffer is recorded synchronously.
                // When we `submit([cmdBuf])`, the queue ops submitted *before* it run first.
                // But we can't interleave `queue.writeBuffer` inside a `commandEncoder` recording block effectively for single-submit.
                // Solution: We must `submit` the command buffer for EACH pass if we want to change uniforms in between using `writeBuffer`.
                // OR use a dynamic offset uniform buffer (requires alignment).
                // OR use separate uniform buffers for each slot.

                // Using separate submits is the easiest fix for now without rewriting buffer management.
                // So we will create a command encoder, record pass, finish, submit. Then update uniforms, create new encoder...

                this.device.queue.writeBuffer(this.computeUniformBuffer, 0, uniformArray);

                const passEncoder = this.device.createCommandEncoder();
                const computePass = passEncoder.beginComputePass();

                const pipeline = this.pipelines.get(mode) as GPUComputePipeline;
                if (pipeline) {
                    const bindGroup = this.getComputeBindGroup(pipeline, currentInputTexture.createView(), targetTexture.createView());
                    computePass.setPipeline(pipeline);
                    computePass.setBindGroup(0, bindGroup);
                    computePass.dispatchWorkgroups(Math.ceil(this.canvas.width / 8), Math.ceil(this.canvas.height / 8), 1);
                }
                computePass.end();
                this.device.queue.submit([passEncoder.finish()]);

                // Swap Input for next pass
                currentInputTexture = targetTexture;
            }

            this.swapDepthTextures();
        } else {
            // No compute shaders active.
            // Check if we need to copy input to writeTexture manually?
            // If the render mode is 'image' or 'video' or 'galaxy', those have their own render pipelines that read directly from source.
            // If the render mode is just 'liquid-render' (default), it reads from `writeTexture`.
            // If no compute shader ran, `writeTexture` is stale or empty.
            // We should copy currentInputTexture to writeTexture if we want to see the image.

            // However, the `render` method below handles 'image'/'video'/'galaxy' separately.
            // If we are in a mode that relies on `liquid-render` (the default switch case), we expect `writeTexture` to have content.
            // So yes, we should copy input to writeTexture.

            const copyEncoder = this.device.createCommandEncoder();
            // Copy input to writeTexture
             copyEncoder.copyTextureToTexture(
                { texture: currentInputTexture },
                { texture: this.writeTexture },
                [this.canvas.width, this.canvas.height]
            );
            this.device.queue.submit([copyEncoder.finish()]);
        }


        // ---------------------------------------------------------
        // RENDER PASS (To Screen)
        // ---------------------------------------------------------
        // We use the first active mode to decide "Render Mode" logic if it's special (like Galaxy),
        // OR we just use a default 'liquid-render' if we are in a compute chain.
        // Actually, the user selects modes in slots.
        // If Slot 1 is 'galaxy', we might want to render galaxy?
        // But 'galaxy' is a rasterizer shader, not compute.
        // The previous logic allowed 'galaxy' to supersede others.
        // If ANY slot is 'galaxy', should we render galaxy?
        // The user said "maybe 3 slots... sequential". Galaxy doesn't chain with compute easily here (it writes to screen).
        // If the user selects 'galaxy' in Slot 1, and 'ripple' in Slot 2...
        // Galaxy renders to screen. Ripple computes... then where does Ripple go?
        // The request implies "Stack Shaders" (Compute).
        // If a user selects a non-compute shader (Galaxy, Image, Video) in a slot, it breaks the chain logic.
        // I will assume for now that if the *Primary* (first) slot is a Special Render Mode (Galaxy, Image, Video pipeline), we use that.
        // Otherwise, we use the `liquid-render` pipeline which displays the result of the Compute Chain.

        // Let's check if the first mode is a "Render Pipeline Mode".
        const primaryMode = modes[0];

        // Final Render Pass
        const renderEncoder = this.device.createCommandEncoder();
        const textureView = this.context.getCurrentTexture().createView();
        const renderPassDescriptor: GPURenderPassDescriptor = {
            colorAttachments: [{
                view: textureView,
                clearValue: {r: 0.0, g: 0.0, b: 0.0, a: 1.0},
                loadOp: 'clear' as GPULoadOp,
                storeOp: 'store' as GPUStoreOp
            }]
        };
        const passEncoder = renderEncoder.beginRenderPass(renderPassDescriptor);
        const liquidRenderPipeline = this.pipelines.get('liquid-render') as GPURenderPipeline;
        const imageVideoPipeline = this.pipelines.get('imageVideo') as GPURenderPipeline;
        const galaxyPipeline = this.pipelines.get('galaxy') as GPURenderPipeline;

        // Legacy handling / Special modes
        // If modes[0] is 'galaxy', we render galaxy.
        if (primaryMode === 'galaxy' && galaxyPipeline && this.bindGroups.has('galaxy')) {
             this.device.queue.writeBuffer(this.galaxyUniformBuffer, 0, new Float32Array([currentTime, zoom, panX, panY]));
             passEncoder.setPipeline(galaxyPipeline);
             passEncoder.setBindGroup(0, this.bindGroups.get('galaxy')!);
             passEncoder.draw(6);
        } else if (primaryMode === 'video' && imageVideoPipeline && this.bindGroups.has('video')) {
            // Render video pass-through if explicitly selected as primary mode
             const uniformArray = new Float32Array(8);
             uniformArray.set([this.canvas.width, this.canvas.height, this.videoTexture.width, this.videoTexture.height], 0);
             uniformArray.set([currentTime, 0, 0, 0], 4);
             this.device.queue.writeBuffer(this.imageVideoUniformBuffer, 0, uniformArray);
             passEncoder.setPipeline(imageVideoPipeline);
             passEncoder.setBindGroup(0, this.bindGroups.get('video')!);
             passEncoder.draw(4);
        } else if ((primaryMode === 'image' || primaryMode === 'ripple') && imageVideoPipeline && this.bindGroups.has('image')) {
            // Legacy handling for 'image' or 'ripple' if they bypass compute logic, though they shouldn't with new chain.
            // Just treat as fallback to standard liquid render?
            // Actually, if 'image' is selected, it might mean "Just show the image".
            // But we handle that via "No active compute shaders" -> Copy input to writeTexture -> liquid-render.
             if (liquidRenderPipeline && this.bindGroups.has('liquid-render')) {
                passEncoder.setPipeline(liquidRenderPipeline);
                passEncoder.setBindGroup(0, this.bindGroups.get('liquid-render')!);
                passEncoder.draw(4);
            }
        } else {
             // Fallback to liquid-render for all compute shaders
             if (liquidRenderPipeline && this.bindGroups.has('liquid-render')) {
                passEncoder.setPipeline(liquidRenderPipeline);
                passEncoder.setBindGroup(0, this.bindGroups.get('liquid-render')!);
                passEncoder.draw(4);
            }
        }

        passEncoder.end();
        this.device.queue.submit([renderEncoder.finish()]);
    }
}
