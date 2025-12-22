import time
from playwright.sync_api import sync_playwright

def verify(page):
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    # Wait for the select element to be populated
    print("Waiting for Sonar Pulse option...")
    try:
        page.wait_for_selector('option[value="sonar-pulse"]', state="attached", timeout=10000)
        print("Sonar Pulse option found in DOM.")
    except Exception:
        print("Sonar Pulse option NOT found within timeout.")
        page.screenshot(path="/home/jules/verification/debug_not_found.png")
        raise

    # Locate the select for Slot 1.
    selects = page.locator('.stack-controls select').all()
    if len(selects) < 3:
        print("Could not find stack selects.")
        pass

    print(f"Found {len(selects)} selects in stack controls.")
    slot1_select = selects[0]

    print("Selecting Sonar Pulse...")
    slot1_select.select_option('sonar-pulse')

    # Wait a bit for React to update state and re-render controls
    time.sleep(1)

    # Take screenshot of controls
    controls = page.locator('.controls')
    controls.screenshot(path="/home/jules/verification/sonar_pulse_selected.png")
    print("Screenshot saved: sonar_pulse_selected.png")

    print("Selecting Hexagon Mosaic...")
    slot1_select.select_option('hex-mosaic')
    time.sleep(1)

    controls.screenshot(path="/home/jules/verification/hex_mosaic_selected.png")
    print("Screenshot saved: hex_mosaic_selected.png")

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
        finally:
            browser.close()
