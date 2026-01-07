
import time
from playwright.sync_api import sync_playwright

def verify_shaders():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        page = context.new_page()

        # Listen to console
        page.on("console", lambda msg: print(f"CONSOLE: {msg.text}"))
        page.on("pageerror", lambda err: print(f"PAGE ERROR: {err}"))

        # Mock WebGPU to avoid crash and allow initialization
        page.add_init_script("""
        Object.defineProperty(navigator, 'gpu', {
            value: {
                requestAdapter: async () => ({
                    features: { has: () => true },
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
                        createBuffer: () => ({}),
                        createTexture: () => ({
                            createView: () => ({}),
                            destroy: () => {}
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
                            copyTextureToTexture: () => {},
                            finish: () => {}
                        }),
                        queue: {
                            writeBuffer: () => {},
                            writeTexture: () => {},
                            submit: () => {},
                            copyExternalImageToTexture: () => {}
                        },
                        destroy: () => {}
                    })
                }),
                getPreferredCanvasFormat: () => 'bgra8unorm'
            }
        });
        HTMLCanvasElement.prototype.getContext = function(type) {
            if (type === 'webgpu') {
                return {
                    configure: () => {},
                    getCurrentTexture: () => ({
                        createView: () => ({})
                    })
                };
            }
            return this._getContext ? this._getContext(type) : null;
        };
        """)

        try:
            print("Navigating to app...")
            page.goto("http://localhost:3000")

            # Wait for potential fetch
            time.sleep(5)

            # Wait for controls to load
            print("Waiting for .stack-controls select...")
            page.wait_for_selector(".stack-controls select", state="attached", timeout=30000)

            # Get options from the first select (Slot 1)
            select_handle = page.query_selector_all(".stack-controls select")[0]
            options = select_handle.query_selector_all("option")
            texts = [opt.inner_text() for opt in options]

            print("Found options:", texts)

            # Verify our new shaders are present
            assert "Rainy Window" in texts, "Rainy Window not found in dropdown"
            assert "Kinetic Echo" in texts, "Kinetic Echo not found in dropdown"

            print("Success! Shaders found.")

            page.screenshot(path="verification/verification.png", full_page=True)

        except Exception as e:
            print(f"Error: {e}")
            page.screenshot(path="verification/error.png")
            raise e
        finally:
            browser.close()

if __name__ == "__main__":
    verify_shaders()
