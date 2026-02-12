from playwright.sync_api import sync_playwright
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=["--no-sandbox", "--disable-setuid-sandbox"])
        page = browser.new_page()

        # Mock WebGPU
        page.add_init_script("""
            const mockFeatures = {
                has: (feature) => true,
                entries: () => [],
                keys: () => [],
                values: () => [],
                forEach: () => {},
                [Symbol.iterator]: function* () {}
            };

            const mockGPU = {
                requestAdapter: async () => ({
                    requestDevice: async () => ({
                        createShaderModule: () => ({
                            getCompilationInfo: async () => ({ messages: [] })
                        }),
                        createComputePipeline: () => ({
                            getBindGroupLayout: () => ({})
                        }),
                        createComputePipelineAsync: async () => ({
                            getBindGroupLayout: () => ({})
                        }),
                        createRenderPipeline: () => ({
                            getBindGroupLayout: () => ({})
                        }),
                        createRenderPipelineAsync: async () => ({
                            getBindGroupLayout: () => ({})
                        }),
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
                            copyBufferToBuffer: () => {},
                            copyBufferToTexture: () => {},
                            copyTextureToBuffer: () => {},
                            finish: () => ({})
                        }),
                        createBindGroup: () => ({}),
                        createBindGroupLayout: () => ({}),
                        createPipelineLayout: () => ({}),
                        createBuffer: () => ({
                            destroy: () => {},
                            mapAsync: async () => {},
                            getMappedRange: () => new ArrayBuffer(0),
                            unmap: () => {}
                        }),
                        createTexture: () => ({
                            destroy: () => {},
                            createView: () => ({})
                        }),
                        createSampler: () => ({}),
                        createQuerySet: () => ({ destroy: () => {} }),
                        queue: {
                            submit: () => {},
                            writeBuffer: () => {},
                            writeTexture: () => {},
                            copyExternalImageToTexture: () => {},
                            copyTextureToBuffer: () => {},
                            copyBufferToTexture: () => {}
                        },
                        destroy: () => {},
                        limits: { maxComputeWorkgroupStorageSize: 16384 },
                        features: mockFeatures
                    }),
                    limits: { maxComputeWorkgroupStorageSize: 16384 },
                    features: mockFeatures,
                    isFallbackAdapter: false
                }),
                getPreferredCanvasFormat: () => 'rgba8unorm'
            };

            try {
                Object.defineProperty(navigator, 'gpu', {
                    value: mockGPU,
                    writable: true
                });
            } catch (e) {
                console.error("Failed to mock navigator.gpu", e);
            }

            // Mock Canvas getContext('webgpu')
            const originalGetContext = HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext = function(type) {
                if (type === 'webgpu') {
                    return {
                        getCurrentTexture: () => ({ createView: () => ({}) }),
                        configure: () => {},
                        canvas: this
                    };
                }
                return originalGetContext.apply(this, arguments);
            };
        """)

        try:
            print("Navigating to http://localhost:3000")
            page.goto("http://localhost:3000")

            # Wait for network idle to ensure resources are loaded
            try:
                page.wait_for_load_state("networkidle", timeout=10000)
            except:
                print("Timeout waiting for networkidle, continuing...")

            # Take a screenshot of the initial state
            page.screenshot(path="verification/initial_load.png")
            print("Initial screenshot taken.")

            # Click "Generative" radio button
            print("Clicking 'Generative' mode...")
            try:
                page.click("text=Generative")
                print("Clicked Generative.")
            except Exception as e:
                print(f"Failed to click Generative: {e}")

            # Look for the dropdown option
            print("Waiting for 'Isometric Cyber-City' option...")
            try:
                # Wait for the option to be attached to the DOM (even if hidden inside select)
                option = page.wait_for_selector('option:has-text("Isometric Cyber-City")', state="attached", timeout=10000)
                if option:
                    print("Found 'Isometric Cyber-City' option!")

                    # Find the parent select element
                    select_handle = option.evaluate_handle('el => el.parentElement')

                    # Get the value of the option
                    val = option.get_attribute("value")
                    print(f"Option value: {val}")

                    # Select the option using the parent select
                    select_handle.as_element().select_option(value=val)
                    print("Selected the option.")

                    # Wait for UI to update (parameters might appear)
                    page.wait_for_timeout(2000)

                    # Check for parameters
                    try:
                        page.wait_for_selector("text=Traffic Speed", timeout=5000)
                        print("Found parameter 'Traffic Speed'.")
                    except:
                        print("Could not find parameter 'Traffic Speed'.")

                    # Take final screenshot
                    page.screenshot(path="verification/verification.png")
                    print("Final screenshot taken at verification/verification.png")
                else:
                    print("Option not found (returned None).")

            except Exception as e:
                print(f"Error finding/selecting option: {e}")
                page.screenshot(path="verification/error.png")

        except Exception as e:
            print(f"Script failed: {e}")
            page.screenshot(path="verification/crash.png")
        finally:
            browser.close()

if __name__ == "__main__":
    run()
