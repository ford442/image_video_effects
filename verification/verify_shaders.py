from playwright.sync_api import sync_playwright, Page, expect

def run(playwright):
    browser = playwright.chromium.launch(
        headless=True,
        args=['--no-sandbox', '--disable-setuid-sandbox']
    )
    context = browser.new_context()
    page = context.new_page()

    # Mock WebGPU
    page.add_init_script("""
        // Mock Navigator.gpu
        if (!navigator.gpu) {
            navigator.gpu = {
                requestAdapter: async () => ({
                    features: { has: (f) => true }, // Mock features.has
                    requestDevice: async () => ({
                        destroy: () => {},
                        queue: {
                            submit: () => {},
                            writeBuffer: () => {},
                            writeTexture: () => {},
                            copyExternalImageToTexture: () => {},
                            copyTextureToTexture: () => {}
                        },
                        createCommandEncoder: () => ({
                            beginComputePass: () => ({
                                setPipeline: () => {},
                                setBindGroup: () => {},
                                dispatchWorkgroups: () => {},
                                end: () => {}
                            }),
                            beginRenderPass: () => ({
                                setPipeline: () => {},
                                setBindGroup: () => {},
                                draw: () => {},
                                end: () => {}
                            }),
                            copyTextureToTexture: () => {},
                            finish: () => {}
                        }),
                        createBindGroup: () => ({}),
                        createBindGroupLayout: () => ({}),
                        createPipelineLayout: () => ({}),
                        createShaderModule: () => ({}),
                        createRenderPipelineAsync: async () => ({
                            getBindGroupLayout: () => ({})
                        }),
                        createComputePipelineAsync: async () => ({
                            getBindGroupLayout: () => ({})
                        }),
                        createBuffer: () => ({ destroy: () => {} }),
                        createTexture: () => ({
                            createView: () => ({}),
                            destroy: () => {},
                            width: 100, height: 100
                        }),
                        createSampler: () => ({}),
                        limits: {
                            maxTextureDimension2D: 8192
                        }
                    })
                }),
                getPreferredCanvasFormat: () => 'rgba8unorm'
            };
        }

        // Mock Canvas getContext for WebGPU
        const originalGetContext = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function(type) {
            if (type === 'webgpu') {
                return {
                    configure: () => {},
                    getCurrentTexture: () => ({
                        createView: () => ({})
                    })
                };
            }
            return originalGetContext.apply(this, arguments);
        };
    """)

    # Catch console errors
    page.on("console", lambda msg: print(f"Console: {msg.text}"))
    page.on("pageerror", lambda err: print(f"Page Error: {err}"))

    try:
        print("Navigating to http://localhost:3000")
        page.goto("http://localhost:3000", timeout=60000)

        print("Waiting for controls...")
        # Wait for the sidebar controls to appear
        page.wait_for_selector(".sidebar", state="visible", timeout=30000)

        print("Waiting for stack controls...")
        # Wait for shader dropdowns
        page.wait_for_selector(".stack-controls select", state="attached", timeout=30000)

        # Get all options from the first dropdown
        options = page.eval_on_selector_all(".stack-controls select option", "opts => opts.map(o => o.text)")

        # Check for new shaders
        new_shaders = ["Neon Contour", "Cyber Rain", "Liquid Warp", "Chromatic Focus"]
        found = []
        for shader in new_shaders:
            if any(shader in opt for opt in options):
                found.append(shader)
                print(f"Found: {shader}")
            else:
                print(f"MISSING: {shader}")

        if len(found) == len(new_shaders):
            print("SUCCESS: All new shaders found in dropdown.")
        else:
            print(f"FAILURE: Only found {len(found)}/{len(new_shaders)} shaders.")

        # Open the dropdown to see options in screenshot
        # We can't easily open native select dropdowns in screenshots usually, but we can verify presence.

        page.screenshot(path="verification/verification.png", full_page=True)

    except Exception as e:
        print(f"Error: {e}")
        page.screenshot(path="verification/error.png")
    finally:
        browser.close()

if __name__ == "__main__":
    with sync_playwright() as p:
        run(p)
