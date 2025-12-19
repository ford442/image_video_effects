import time
from playwright.sync_api import sync_playwright

def verify(page):
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    # Wait for the select element to be populated
    print("Waiting for Magnetic Interference option...")
    try:
        # Wait for the options to be present in the DOM (attached state)
        page.wait_for_selector('option[value="magnetic-interference"]', state="attached", timeout=15000)
        print("Magnetic Interference option found in DOM.")
    except Exception:
        print("Magnetic Interference option NOT found within timeout.")
        page.screenshot(path="debug_not_found.png")
        raise

    # Locate the select for Slot 1.
    selects = page.locator('.stack-controls select').all()
    if len(selects) < 3:
        print("Could not find stack selects.")
        raise Exception("Stack selects not found")

    print(f"Found {len(selects)} selects in stack controls.")
    slot1_select = selects[0]

    print("Selecting Magnetic Interference...")
    slot1_select.select_option('magnetic-interference')

    # Wait a bit for React to update state and re-render controls
    time.sleep(2)

    # Check for parameter labels
    content = page.content()
    if "Strength" in content and "Aberration" in content:
        print("Magnetic Interference params found.")
    else:
        print("Magnetic Interference params MISSING.")
        raise Exception("Params missing for magnetic-interference")

    controls = page.locator('.controls')
    controls.screenshot(path="magnetic_interference_selected.png")
    print("Screenshot saved: magnetic_interference_selected.png")

    print("Selecting Neon Strings...")
    slot1_select.select_option('neon-strings')
    time.sleep(2)

    content = page.content()
    if "Edge Threshold" in content and "Neon Intensity" in content:
        print("Neon Strings params found.")
    else:
        print("Neon Strings params MISSING.")
        raise Exception("Params missing for neon-strings")

    controls.screenshot(path="neon_strings_selected.png")
    print("Screenshot saved: neon_strings_selected.png")

if __name__ == "__main__":
    with sync_playwright() as p:
        print("Launching browser...")
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Inject WebGPU Mock
        page.add_init_script("""
            Object.defineProperty(navigator, 'gpu', {
              value: {
                getPreferredCanvasFormat: () => 'bgra8unorm',
                requestAdapter: async () => ({
                  limits: {
                    maxComputeWorkgroupStorageSize: 16384,
                    maxStorageBufferBindingSize: 134217728
                  },
                  features: {
                    has: (feature) => true
                  },
                  requestDevice: async () => ({
                    createBindGroup: () => {},
                    createBindGroupLayout: () => {},
                    createPipelineLayout: () => {},
                    createShaderModule: () => {},
                    createComputePipelineAsync: async () => ({
                        getBindGroupLayout: () => {}
                    }),
                    createRenderPipelineAsync: async () => ({
                        getBindGroupLayout: () => {}
                    }),
                    createComputePipeline: () => {},
                    createRenderPipeline: () => {},
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
                        setVertexBuffer: () => {},
                        draw: () => {},
                        end: () => {}
                      }),
                      copyTextureToTexture: () => {},
                      finish: () => {}
                    }),
                    queue: {
                      submit: () => {},
                      writeBuffer: () => {},
                      writeTexture: () => {},
                      copyExternalImageToTexture: () => {}
                    },
                    createBuffer: () => ({ destroy: () => {} }),
                    createTexture: () => ({ createView: () => {}, destroy: () => {} }),
                    createSampler: () => {}
                  })
                })
              }
            });

            const origGetContext = HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext = function(type) {
                if (type === 'webgpu') {
                    return {
                        configure: () => {},
                        getCurrentTexture: () => ({ createView: () => {} })
                    };
                }
                return origGetContext.call(this, type);
            };
        """)

        try:
            verify(page)
        except Exception as e:
            print(f"Error: {e}")
            exit(1)
        finally:
            browser.close()
