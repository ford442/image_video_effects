import time
from playwright.sync_api import sync_playwright

def run(playwright):
    browser = playwright.chromium.launch(headless=True)
    # Mock WebGPU for headless environment
    context = browser.new_context()

    # Inject script to mock navigator.gpu
    context.add_init_script("""
        if (!navigator.gpu) {
            navigator.gpu = {
                requestAdapter: async () => ({
                    requestDevice: async () => ({
                        createShaderModule: () => ({}),
                        createRenderPipelineAsync: async () => ({
                             getBindGroupLayout: () => ({})
                        }),
                        createComputePipelineAsync: async () => ({
                             getBindGroupLayout: () => ({})
                        }),
                        createBindGroup: () => ({}),
                        createBindGroupLayout: () => ({}),
                        createPipelineLayout: () => ({}),
                        createTexture: () => ({
                            createView: () => ({}),
                            destroy: () => {}
                        }),
                        createSampler: () => ({}),
                        createBuffer: () => ({ destroy: () => {} }),
                        createCommandEncoder: () => ({
                            beginRenderPass: () => ({
                                setPipeline: () => {},
                                setBindGroup: () => {},
                                draw: () => {},
                                end: () => {}
                            }),
                            beginComputePass: () => ({
                                setPipeline: () => {},
                                setBindGroup: () => {},
                                dispatchWorkgroups: () => {},
                                end: () => {}
                            }),
                            finish: () => {},
                            copyTextureToTexture: () => {},
                            copyExternalImageToTexture: () => {},
                            writeBuffer: () => {},
                            writeTexture: () => {}
                        }),
                        queue: {
                            submit: () => {},
                            writeBuffer: () => {},
                            writeTexture: () => {},
                            copyExternalImageToTexture: () => {}
                        },
                        destroy: () => {}
                    }),
                    features: { has: () => true }
                }),
                getPreferredCanvasFormat: () => 'bgra8unorm'
            };

            // Mock Canvas Context
            const originalGetContext = HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext = function(type) {
                if (type === 'webgpu') {
                    return {
                        configure: () => {},
                        getCurrentTexture: () => ({ createView: () => ({}) })
                    };
                }
                return originalGetContext.apply(this, arguments);
            };
        }
    """)

    page = context.new_page()

    # Enable console logging
    page.on("console", lambda msg: print(f"Browser Console: {msg.text}"))
    page.on("pageerror", lambda err: print(f"Browser Error: {err}"))

    try:
        print("Navigating to http://localhost:3000...")
        page.goto("http://localhost:3000")

        # Wait for app to load
        print("Waiting for app to load...")
        # Check for specific UI elements added in Controls.tsx
        page.wait_for_selector("text=Pixelocity", timeout=20000)

        print("Checking for Image Source radio buttons...")
        # My Controls.tsx implementation doesn't use value attribute, just checked state.
        # Use a more generic selector or text.
        page.wait_for_selector("text=Image")
        page.wait_for_selector("input[type=radio]")

        print("Checking for Upload Img button...")
        page.wait_for_selector("button:has-text('Upload Img')")

        print("Checking for AutoDJ controls...")
        # "Start AI VJ" button
        page.wait_for_selector("button:has-text('Start AI VJ')")

        # Take screenshot of the UI
        print("Taking screenshot...")
        page.screenshot(path="verification/ui_verification.png", full_page=True)
        print("Screenshot saved to verification/ui_verification.png")

    except Exception as e:
        print(f"Test failed: {e}")
        page.screenshot(path="verification/error_screenshot.png")
    finally:
        browser.close()

with sync_playwright() as playwright:
    run(playwright)
