import os
from playwright.sync_api import sync_playwright, expect

def verify_shader_presence(page):
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    # Wait for the select dropdown to be available
    print("Waiting for controls...")
    try:
        page.wait_for_selector(".stack-controls select", state="attached", timeout=15000)
    except:
        print("Timeout waiting for controls.")
        page.screenshot(path="verification_timeout.png", full_page=True)
        return

    # Give it a moment for the options to populate via the async effect
    page.wait_for_timeout(4000)

    select_locator = page.locator(".stack-controls select").first
    options = select_locator.inner_text()

    print(f"Options found length: {len(options)}")

    found_rain = "Pixel Rain" in options
    found_vortex = "Vortex Warp" in options

    print(f"Pixel Rain found: {found_rain}")
    print(f"Vortex Warp found: {found_vortex}")

    if not found_rain or not found_vortex:
        print("FAIL: Shaders not found in dropdown.")
    else:
        print("SUCCESS: Both shaders found in dropdown.")

    if found_rain:
        print("Selecting Pixel Rain...")
        select_locator.select_option(label="Pixel Rain")
        page.wait_for_timeout(1000)

        content = page.content()
        if "Rain Speed" in content and "Glitch / Tint" in content:
            print("SUCCESS: Pixel Rain params visible.")
        else:
            print("FAIL: Pixel Rain params NOT visible.")

    page.screenshot(path="verification_shaders_v3.png", full_page=True)

if __name__ == "__main__":
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=["--enable-unsafe-webgpu"])
        context = browser.new_context()

        # Inject WebGPU mock with ALL required methods
        context.add_init_script("""
        Object.defineProperty(navigator, 'gpu', {
            value: {
                requestAdapter: async () => ({
                    limits: {
                         maxComputeWorkgroupStorageSize: 16384,
                         maxTextureDimension2D: 8192,
                    },
                    features: { has: (feature) => true },
                    requestDevice: async () => ({
                        createBuffer: () => ({ destroy: () => {} }),
                        createTexture: () => ({ createView: () => ({}), destroy: () => {} }),
                        createSampler: () => ({}),
                        createBindGroupLayout: () => ({}),
                        createPipelineLayout: () => ({}),
                        createBindGroup: () => ({}),
                        createShaderModule: () => ({}),
                        createRenderPipelineAsync: async () => ({}),
                        createComputePipelineAsync: async () => ({}),
                        createCommandEncoder: () => ({
                            beginRenderPass: () => ({
                                setPipeline: () => {},
                                setBindGroup: () => {},
                                setVertexBuffer: () => {},
                                setViewport: () => {},
                                draw: () => {},
                                end: () => {}
                            }),
                            beginComputePass: () => ({
                                setPipeline: () => {},
                                setBindGroup: () => {},
                                dispatchWorkgroups: () => {},
                                end: () => {}
                            }),
                            copyTextureToTexture: () => {},
                            finish: () => ({})
                        }),
                        queue: {
                            submit: () => {},
                            writeBuffer: () => {},
                            writeTexture: () => {},
                            copyExternalImageToTexture: () => {}
                        }
                    })
                }),
                getPreferredCanvasFormat: () => 'bgra8unorm'
            }
        });

        const getContextOriginal = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function(type) {
            if (type === 'webgpu') {
                return {
                    configure: () => {},
                    canvas: this
                };
            }
            return getContextOriginal.apply(this, arguments);
        };
        """)

        page = context.new_page()
        verify_shader_presence(page)
        browser.close()
