
import time
from playwright.sync_api import sync_playwright

def verify_shaders():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        page = context.new_page()

        # Listen for console logs
        page.on("console", lambda msg: print(f"CONSOLE: {msg.text}"))
        page.on("pageerror", lambda exc: print(f"PAGE ERROR: {exc}"))

        # Mock WebGPU to allow the app to load
        page.add_init_script("""
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

        Object.defineProperty(navigator, 'gpu', {
            value: {
                requestAdapter: async () => ({
                    features: { has: (feature) => true },
                    limits: {},
                    requestDevice: async () => ({
                        createBuffer: () => ({}),
                        createTexture: () => ({
                            createView: () => ({}),
                            destroy: () => {},
                            width: 100,
                            height: 100
                        }),
                        createSampler: () => ({}),
                        createBindGroupLayout: () => ({}),
                        createPipelineLayout: () => ({}),
                        createBindGroup: () => ({}),
                        createRenderPipelineAsync: async () => ({
                            getBindGroupLayout: (index) => ({})
                        }),
                        createComputePipelineAsync: async () => ({
                            getBindGroupLayout: (index) => ({})
                        }),
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
                            finish: () => ({}),
                            copyTextureToTexture: () => {}
                        }),
                        queue: {
                            submit: () => {},
                            writeBuffer: () => {},
                            writeTexture: () => {},
                            copyExternalImageToTexture: () => {}
                        },
                        destroy: () => {},
                        features: { has: (feature) => true },
                        createShaderModule: () => ({}),
                    }),
                }),
                getPreferredCanvasFormat: () => 'rgba8unorm'
            }
        });
        """)

        # Navigate to the app
        print("Navigating to app...")
        page.goto("http://localhost:3000")

        # Wait for the app to load
        try:
            page.wait_for_selector(".stack-controls select", state="attached", timeout=10000)
            print("Controls loaded.")
        except:
            print("Timeout waiting for controls. Taking screenshot of current state.")
            page.screenshot(path="verification/error_state.png")
            return

        # Wait a bit for lists to populate
        time.sleep(3)

        # Take a screenshot
        page.screenshot(path="verification/debug_state.png")

        # Select the category filter if needed, but it should default to 'image'
        try:
            category_select = page.locator("#category-select")
            if category_select.count() > 0:
                print(f"Category filter value: {category_select.input_value()}")
                if category_select.input_value() != "image":
                    category_select.select_option("image")
                    time.sleep(1)
        except Exception as e:
            print(f"Error checking category: {e}")

        # Check shader dropdowns
        shader_selects = page.locator(".stack-controls select").all()

        if len(shader_selects) > 0:
            options = shader_selects[0].locator("option").all_inner_texts()
            print(f"Found {len(options)} options in first dropdown.")
            if len(options) > 1:
                print("First 10 options:", options[:10])

            found_neon = "Neon Wake" in options
            found_luma = "Luma Ripple" in options

            if found_neon:
                print("SUCCESS: 'Neon Wake' found.")
            else:
                print("FAILURE: 'Neon Wake' NOT found.")

            if found_luma:
                print("SUCCESS: 'Luma Ripple' found.")
            else:
                print("FAILURE: 'Luma Ripple' NOT found.")

             # Select Luma Ripple
            if found_luma:
                shader_selects[0].select_option(label="Luma Ripple")
                time.sleep(1)
                page.screenshot(path="verification/luma_ripple_selected.png")
                print("Screenshot taken: verification/luma_ripple_selected.png")
        else:
            print("No shader selects found in .stack-controls")

        browser.close()

if __name__ == "__main__":
    verify_shaders()
