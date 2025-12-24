import {RenderMode, ShaderEntry, InputSource, SlotParams} from './types';

export class Renderer {
    private canvas: HTMLCanvasElement;
    private device!: GPUDevice;
    private context!: GPUCanvasContext;
    private presentationFormat!: GPUTextureFormat;
    private pipelines = new Map<string, GPURenderPipeline | GPUComputePipeline>();
    private bindGroups = new Map<string, GPUBindGroup>();
    private dynamicBindGroups = new Map<string, GPUBindGroup>();
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
    
    // Lifecycle flag to prevent race conditions
    private isDestroyed = false;

    // Store layout to create pipelines lazily
    private computePipelineLayout!: GPUPipelineLayout;
    private loadingShaders = new Set<string>();

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
        if (this.isDestroyed) return;
        this.inputSource = source;
        this.createBindGroups();
    }

    public addRipplePoint(x: number, y: number) {
        this.ripplePoints.push({x, y, startTime: performance.now() / 1000.0});
    }

    public firePlasma(x: number, y: number, vx: number, vy: number) {
        if (this.plasmaBalls.length >= this.MAX_PLASMA_BALLS) return;
        const r = 0.8 + Math.random() * 0.2;
        const g = Math.random() * 0.6;
        const b = Math.random() * 0.2;

        this.plasmaBalls.push({
            x, y, vx, vy,
            r, g, b,
            radius: 0.05 + Math.random() * 0.08,
            age: 0,
            maxAge: 5.0 + Math.random() * 5.0,
            seed: Math.random() * 100.0
        });
    }

    private updatePlasma(dt: number) {
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
                this.plasmaBalls.splice(i, 1);
            }
        }

        for (let i = 0; i < this.plasmaBalls.length; i++) {
            for (let j = i + 1; j < this.plasmaBalls.length; j++) {
                const b1 = this.plasmaBalls[i];
                const b2 = this.plasmaBalls[j];

                const dx = b2.x - b1.x;
                const dy = b2.y - b1.y;
                const dist = Math.sqrt(dx*dx + dy*dy);
                const minDist = b1.radius + b2.radius;

                if (dist < minDist && dist > 0.0001) {
                    const nx = dx / dist;
                    const ny = dy / dist;
                    const dvx = b1.vx - b2.vx;
                    const dvy = b1.vy - b2.vy;
                    const normalVel = dvx * nx + dvy * ny;
                    if (normalVel < 0) continue;
                    const impulse = -normalVel;

                    b1.vx += impulse * nx;
                    b1.vy += impulse * ny;
                    b2.vx -= impulse * nx;
                    b2.vy -= impulse * ny;

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
        this.isDestroyed = true; // Mark as destroyed immediately
        
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
        if (this.isDestroyed) return false;
        if (!navigator.gpu) return false;
        
        const adapter = await navigator.gpu.requestAdapter();
        if (this.isDestroyed || !adapter) return false;

        const requiredFeatures: GPUFeatureName[] = [];
        const featureCheck = [
            'float32-filterable', 'float32-blendable', 'clip-distances', 
            'depth32float-stencil8', 'dual-source-blending', 'subgroups', 
            'texture-component-swizzle', 'shader-f16'
        ];
        
        featureCheck.forEach(f => {
            if (adapter.features.has(f)) requiredFeatures.push(f as GPUFeatureName);
        });
        
        // Initialize Device
        this.device = await adapter.requestDevice({
            requiredFeatures,
        });

        if (this.isDestroyed) {
            this.device.destroy();
            return false;
        }

        this.context = this.canvas.getContext('webgpu')!;
        this.presentationFormat = navigator.gpu.getPreferredCanvasFormat();
        this.context.configure({device: this.device, colorSpace: "display-p3", format: this.presentationFormat, alphaMode: 'premultiplied', toneMapping: {mode: "extended"}});
        
        await this.fetchImageUrls();
        if (this.isDestroyed) return false;

        await this.fetchShaderList();
        if (this.isDestroyed) return false;

        await this.createResources();
        if (this.isDestroyed) return false;

        await this.createPipelines();
        if (this.isDestroyed) return false;

        await this.loadRandomImage();
        
        return !this.isDestroyed;
    }

    private async fetchShaderList(): Promise<void> {
        if (this.isDestroyed) return;
        try {
            const categories = [
                'liquid-effects',
                'interactive-mouse',
                'visual-effects',
                'lighting-effects',
                'distortion',
                'artistic'
            ];
            
            const allShaders: ShaderEntry[] = [];
            
            for (const category of categories) {
                if (this.isDestroyed) return;
                try {
                    const response = await fetch(`shader-lists/${category}.json`);
                    if (response.ok) {
                        const shaders = await response.json();
                        allShaders.push(...shaders);
                    } else {
                        console.warn(`Failed to load category ${category}: ${response.status}`);
                    }
                } catch (e) {
                    console.warn(`Failed to load category ${category}:`, e);
                }
            }
            
            this.shaderList = allShaders;
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
            if (this.isDestroyed) return;

            this.imageUrls = data.items ? data.items
                .filter((item: { name: string }) => /\.(jpg|jpeg|png|webp|gif)$/i.test(item.name))
                .map((item: {
                name: string
            }) => `https://storage.googleapis.com/${bucketName}/${item.name}`) : [];
        } catch (e) {
            console.error("Failed to fetch image list:", e);
            this.imageUrls = ['https://i.imgur.com/vCNL2sT.jpeg'];
        }
    }

    // New Method to load specific image (URL or Blob)
    public async loadImage(url: string): Promise<string | undefined> {
        if (this.isDestroyed) return undefined;
        try {
             const response = await fetch(url);
             const blob = await response.blob();
             const imageBitmap = await createImageBitmap(blob);
             
             if (this.isDestroyed) return undefined;

             if (this.imageTexture) this.imageTexture.destroy();
             this.imageTexture = this.device.createTexture({
                 size: [imageBitmap.width, imageBitmap.height],
                 format: 'rgba32float',
                 usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
             });
             this.device.queue.copyExternalImageToTexture({source: imageBitmap}, {texture: this.imageTexture, colorSpace:"display-p3"}, [imageBitmap.width, imageBitmap.height]);
             this.createBindGroups();
             return url;
        } catch(e) {
            console.error("Failed to load image:", url, e);
            return undefined;
        }
    }

    public async loadRandomImage(): Promise<string | undefined> {
        if (this.imageUrls.length === 0) return;
        const imageUrl = this.imageUrls[Math.floor(Math.random() * this.imageUrls.length)];
        return this.loadImage(imageUrl);
    }

    public updateDepthMap(data: Float32Array, width: number, height: number): void {
        if (!this.device || this.isDestroyed) return;
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
        if (this.isDestroyed) return;
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
            usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.COPY_SRC,
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
            size: this.MAX_PLASMA_BALLS * 48,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        });
    }

    private async createPipelines(): Promise<void> {
        if (this.isDestroyed) return;

        const commonConfig = {
            vertex: {module: null as any, entryPoint: 'vs_main'},
            fragment: {targets: [{format: this.presentationFormat}]},
            primitive: {topology: 'triangle-strip' as GPUPrimitiveTopology}
        };

        const staticShaders = ['galaxy.wgsl', 'imageVideo.wgsl', 'texture.wgsl'];
        const staticCodes = await Promise.all(staticShaders.map(name => fetch(`shaders/${name}`).then(r => r.text())));
        if (this.isDestroyed) return;
        
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

        // Store layout for lazy loading
        this.computePipelineLayout = this.device.createPipelineLayout({
            bindGroupLayouts: [computeBindGroupLayout],
        });
        
        // LAZY LOADING OPTIMIZATION: 
        // We no longer loop through this.shaderList here. 
        // Shaders will be compiled on-demand in loadComputeShader()
    }

    private async loadComputeShader(id: string): Promise<void> {
        if (this.pipelines.has(id) || this.loadingShaders.has(id)) return;
        
        const entry = this.shaderList.find(s => s.id === id);
        if (!entry) return;

        this.loadingShaders.add(id);
        
        try {
            const url = entry.url;
            const code = await fetch(url).then(r => r.text());
            
            if (this.isDestroyed) return;

            const module = this.device.createShaderModule({code});

            const pipeline = await this.device.createComputePipelineAsync({
                layout: this.computePipelineLayout,
                compute: {module, entryPoint: 'main'}
            });
            
            if (this.isDestroyed) return;
            this.pipelines.set(entry.id, pipeline);
        } catch (e) {
            console.error(`Failed to load shader ${id}:`, e);
        } finally {
            this.loadingShaders.delete(id);
        }
    }

    private createBindGroups(): void {
        if (this.isDestroyed) return;
        if (!this.imageTexture || !this.filteringSampler || !this.nonFilteringSampler || !this.comparisonSampler || !this.depthTextureRead || !this.depthTextureWrite || !this.dataTextureA|| !this.dataTextureB || !this.dataTextureC || !this.extraBuffer || !this.computeUniformBuffer || !this.plasmaBuffer) return;

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

        this.dynamicBindGroups.clear();
    }

    private getComputeBindGroup(pipeline: GPUComputePipeline, inputView: GPUTextureView, outputView: GPUTextureView): GPUBindGroup {
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
        if (this.isDestroyed || !this.device || !this.imageTexture || !this.filteringSampler) return;
        const currentTime = performance.now() / 1000.0;

        // Handle Video Input (Video or Webcam)
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

        // ---------------------------------------------------------
        // COMPUTE SHADER CHAIN
        // ---------------------------------------------------------

        // Determine input source texture
        let currentInputTexture = this.imageTexture;
        // Accept 'video' or 'webcam' as valid sources for video texture
        if ((this.inputSource === 'video' || this.inputSource === 'webcam') && this.videoTexture) {
            currentInputTexture = this.videoTexture;
        }

        // Filter out 'none' modes
        const activeChain = modes.map((m, i) => ({ mode: m, params: slotParams[i] })).filter(item => {
             return item.mode !== 'none' && this.shaderList.some(s => s.id === item.mode);
        });
        
        // --- LAZY LOADING CHECK ---
        // Filter out shaders that are not yet loaded, triggering their load.
        const readyChain = activeChain.filter(item => {
            if (this.pipelines.has(item.mode)) return true;
            // If not loaded, trigger load and skip this frame
            this.loadComputeShader(item.mode);
            return false;
        });

        if (readyChain.length > 0) {
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

            const rippleLifetime = 4.0;
            this.ripplePoints = this.ripplePoints.filter(p => (currentTime - p.startTime) < rippleLifetime);
            if (this.ripplePoints.length > this.MAX_RIPPLES) this.ripplePoints.splice(0, this.ripplePoints.length - this.MAX_RIPPLES);
            const rippleDataArr = new Float32Array(this.MAX_RIPPLES * 4);
            for (let i = 0; i < this.ripplePoints.length; i++) {
                const point = this.ripplePoints[i];
                rippleDataArr.set([point.x, point.y, point.startTime], i * 4);
            }

            for (let i = 0; i < readyChain.length; i++) {
                const { mode, params } = readyChain[i];
                const isLast = i === readyChain.length - 1;

                let targetTexture: GPUTexture;
                if (isLast) {
                    targetTexture = this.writeTexture;
                } else {
                    targetTexture = (i % 2 === 0) ? this.pingPongTexture1 : this.pingPongTexture2;
                }

                const uniformArray = new Float32Array(12 + this.MAX_RIPPLES * 4);
                
                // Determine target point and zoomConfigW based on Shader Features (Left Side Logic) vs Mode (Right Side Logic)
                let targetX = farthestPoint.x;
                let targetY = farthestPoint.y;
                let zoomConfigW = 0;

                if (mode === 'infinite-zoom') {
                    zoomConfigW = params.depthThreshold; // Infinite zoom uses W for depth threshold
                }

                const shaderEntry = this.shaderList.find(s => s.id === mode);
                if (shaderEntry?.features?.includes('mouse-driven')) {
                    if (mousePosition.x >= 0) {
                        targetX = mousePosition.x;
                        targetY = mousePosition.y;
                    }
                    // For mouse-driven non-infinite-zoom shaders, use W for interaction state
                    if (mode !== 'infinite-zoom') {
                        zoomConfigW = isMouseDown ? 1.0 : 0.0;
                    }
                }

                uniformArray.set([currentTime, targetX, targetY, zoomConfigW], 4);
                uniformArray.set([this.canvas.width, this.canvas.height], 0); 
                // Correct Packing:
                // Vec4 0: [Time, RippleCount, Width, Height]
                uniformArray.set([currentTime, this.ripplePoints.length, this.canvas.width, this.canvas.height], 0); 
                // Vec4 1: [TargetX, TargetY, ZoomConfigW, PADDING] -> overwritten by next steps usually, but we set it above

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

                currentInputTexture = targetTexture;
            }

            this.swapDepthTextures();

            const copyEncoder = this.device.createCommandEncoder();
            copyEncoder.copyTextureToTexture(
                { texture: this.dataTextureA },
                { texture: this.dataTextureC },
                [this.canvas.width, this.canvas.height]
            );
            this.device.queue.submit([copyEncoder.finish()]);
        }

        // ---------------------------------------------------------
        // RENDER PASS (To Screen)
        // ---------------------------------------------------------
        const primaryMode = modes[0];

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

        if (primaryMode === 'galaxy' && galaxyPipeline && this.bindGroups.has('galaxy')) {
             this.device.queue.writeBuffer(this.galaxyUniformBuffer, 0, new Float32Array([currentTime, zoom, panX, panY]));
             passEncoder.setPipeline(galaxyPipeline);
             passEncoder.setBindGroup(0, this.bindGroups.get('galaxy')!);
             passEncoder.draw(6);
        } else if ((primaryMode === 'video' || this.inputSource === 'video' || this.inputSource === 'webcam') && primaryMode === 'video' && imageVideoPipeline && this.bindGroups.has('video')) {
            // Render video pass-through if explicitly selected
             const uniformArray = new Float32Array(8);
             uniformArray.set([this.canvas.width, this.canvas.height, this.videoTexture.width, this.videoTexture.height], 0);
             uniformArray.set([currentTime, 0, 0, 0], 4);
             this.device.queue.writeBuffer(this.imageVideoUniformBuffer, 0, uniformArray);
             passEncoder.setPipeline(imageVideoPipeline);
             passEncoder.setBindGroup(0, this.bindGroups.get('video')!);
             passEncoder.draw(4);
        } else {
             // If active chain exists (and has loaded shaders), render the output texture
             if (readyChain.length > 0) {
                 if (liquidRenderPipeline && this.bindGroups.has('liquid-render')) {
                    passEncoder.setPipeline(liquidRenderPipeline);
                    passEncoder.setBindGroup(0, this.bindGroups.get('liquid-render')!);
                    passEncoder.draw(4);
                }
             } else {
                 // No effects or effects loading. Draw input directly (scaled).
                 const isVideo = (this.inputSource === 'video' || this.inputSource === 'webcam');
                 // Ensure texture exists
                 if ((isVideo && this.videoTexture) || (!isVideo && this.imageTexture)) {
                     const groupName = isVideo ? 'video' : 'image';
                     const texture = isVideo ? this.videoTexture : this.imageTexture;

                     if (imageVideoPipeline && this.bindGroups.has(groupName) && texture) {
                         const uniformArray = new Float32Array(8);
                         uniformArray.set([this.canvas.width, this.canvas.height, texture.width, texture.height], 0);
                         uniformArray.set([currentTime, 0, 0, 0], 4);
                         this.device.queue.writeBuffer(this.imageVideoUniformBuffer, 0, uniformArray);

                         passEncoder.setPipeline(imageVideoPipeline);
                         passEncoder.setBindGroup(0, this.bindGroups.get(groupName)!);
                         passEncoder.draw(4);
                     }
                 }
             }
        }

        passEncoder.end();
        this.device.queue.submit([renderEncoder.finish()]);
    }
}
