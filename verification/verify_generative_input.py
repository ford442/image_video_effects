from playwright.sync_api import sync_playwright, expect

def verify_generative_input(page):
    # Mock WebGPU to avoid crash on headless environments
    page.add_init_script("""
        Object.defineProperty(navigator, 'gpu', {
            value: {
                getPreferredCanvasFormat: () => 'bgra8unorm',
                requestAdapter: async () => ({
                    limits: {
                        maxBufferSize: 268435456,
                        maxStorageBufferBindingSize: 134217728,
                        maxTextureDimension2D: 8192
                    },
                    features: { has: () => true },
                    requestDevice: async () => ({
                        queue: {
                            submit: () => {},
                            writeBuffer: () => {},
                            writeTexture: () => {}
                        },
                        createShaderModule: () => ({}),
                        createPipelineLayout: () => ({}),
                        createRenderPipeline: () => ({}),
                        createRenderPipelineAsync: async () => ({}),
                        createComputePipeline: () => ({
                            getBindGroupLayout: () => ({})
                        }),
                        createComputePipelineAsync: async () => ({
                            getBindGroupLayout: () => ({})
                        }),
                        createBindGroup: () => ({}),
                        createBindGroupLayout: () => ({}),
                        createBuffer: () => ({
                            mapAsync: async () => {},
                            getMappedRange: () => new Float32Array(0),
                            unmap: () => {}
                        }),
                        createTexture: () => ({
                            createView: () => ({})
                        }),
                        createSampler: () => ({}),
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
                            copyTextureToBuffer: () => {},
                            finish: () => ({})
                        }),
                        destroy: () => {}
                    })
                })
            },
            writable: true
        });

        // Mock getContext('webgpu')
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
    """)

    page.goto("http://localhost:3000")

    # Wait for the "Input Source" label to verify app loaded
    page.wait_for_selector("text=Input Source")

    # Locate the Generative radio button
    # The label contains the text "Generative" and has a radio input inside or near it.
    # Based on code: <label><input type="radio" value="generative" ... /> Generative</label>
    generative_label = page.locator("label").filter(has_text="Generative")
    generative_radio = generative_label.locator("input[type='radio']")

    # Locate the Effect Filter dropdown
    # Code: <select id="category-select" ...>
    category_select = page.locator("#category-select")

    # Verify initial state: Effect Filter should be "Effects / Filters" (value="image")
    expect(category_select).to_have_value("image")

    print("Initial state: Effect Filter is 'image'.")

    # Click Generative
    generative_radio.click()

    # Wait a bit for potential side effects (state updates)
    page.wait_for_timeout(1000)

    # Verify: Effect Filter should STILL be "Effects / Filters" (value="image")
    # Before the fix, it would have switched to "shader" (Procedural Generation)
    expect(category_select).to_have_value("image")

    print("Post-click state: Effect Filter is still 'image'. Verification Passed.")

    # Screenshot
    page.screenshot(path="verification/generative_input_verification.png")

if __name__ == "__main__":
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        try:
            verify_generative_input(page)
        except Exception as e:
            print(f"Verification failed: {e}")
            page.screenshot(path="verification/error_state.png")
            raise e
        finally:
            browser.close()
