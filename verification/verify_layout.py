
from playwright.sync_api import sync_playwright
import os

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        # Mock WebGPU before page load
        context = browser.new_context()
        page = context.new_page()

        # Inject WebGPU mock to prevent crash and ensure UI renders
        page.add_init_script("""
            if (!navigator.gpu) {
                navigator.gpu = {
                    requestAdapter: async () => ({
                        requestDevice: async () => ({
                            createBuffer: () => ({}),
                            createTexture: () => ({ createView: () => ({}) }),
                            createSampler: () => ({}),
                            createBindGroupLayout: () => ({}),
                            createPipelineLayout: () => ({}),
                            createBindGroup: () => ({}),
                            createRenderPipelineAsync: async () => ({}),
                            createComputePipelineAsync: async () => ({}),
                            createCommandEncoder: () => ({
                                beginRenderPass: () => ({
                                    setPipeline: () => {},
                                    setBindGroup: () => {},
                                    setVertexBuffer: () => {},
                                    setIndexBuffer: () => {},
                                    draw: () => {},
                                    drawIndexed: () => {},
                                    end: () => {}
                                }),
                                beginComputePass: () => ({
                                    setPipeline: () => {},
                                    setBindGroup: () => {},
                                    dispatchWorkgroups: () => {},
                                    end: () => {}
                                }),
                                copyTextureToTexture: () => {},
                                copyBufferToBuffer: () => {},
                                finish: () => ({})
                            }),
                            queue: {
                                submit: () => {},
                                writeBuffer: () => {},
                                copyExternalImageToTexture: () => {}
                            },
                            features: {
                                has: (feature) => true
                            }
                        }),
                        features: {
                             has: (feature) => true
                        }
                    })
                };
            }
            // Mock Canvas Context
            const originalGetContext = HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext = function(type, options) {
                if (type === 'webgpu') return true;
                return originalGetContext.call(this, type, options);
            };
        """)

        # Load the app
        page.goto('http://localhost:3000')

        # Wait for key elements of the new layout
        page.wait_for_selector('.header', state='visible')
        page.wait_for_selector('.sidebar', state='visible')

        # Verify branding
        title = page.locator('.logo-text').text_content()
        print(f'Found title: {title}')

        # Take screenshot
        page.screenshot(path='verification/new_layout.png', full_page=True)
        browser.close()

if __name__ == '__main__':
    run()
