import time
from playwright.sync_api import sync_playwright

def verify(page):
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    # Wait for the select element to be populated
    # We verify one of our new shaders
    print("Waiting for Charcoal Rubbing option...")
    try:
        page.wait_for_selector('option[value="charcoal-rub"]', state="attached", timeout=10000)
        print("Charcoal Rubbing option found in DOM.")
    except Exception:
        print("Charcoal Rubbing option NOT found within timeout.")
        page.screenshot(path="debug_not_found.png")
        raise

    # Locate the select for Slot 1.
    selects = page.locator('.stack-controls select').all()
    if len(selects) < 3:
        print("Could not find stack selects.")
        # Try finding by general select tag if class locator failed (screenshot showed standard structure)
        selects = page.locator('select').all()
        # Usually filter 1 + 3 stack selects
        if len(selects) >= 4:
            # Index 1 is likely slot 1 (0 is filter)
            selects = selects[1:]

    print(f"Found {len(selects)} selects in stack controls.")
    slot1_select = selects[0]

    # Test 1: Charcoal Rubbing
    print("Selecting Charcoal Rubbing...")
    slot1_select.select_option('charcoal-rub')
    time.sleep(1)
    page.screenshot(path="charcoal_rub_verification.png")
    print("Screenshot saved: charcoal_rub_verification.png")

    # Test 2: Particle Disperse
    print("Selecting Particle Disperse...")
    slot1_select.select_option('particle-disperse')
    time.sleep(1)
    page.screenshot(path="particle_disperse_verification.png")
    print("Screenshot saved: particle_disperse_verification.png")

    # Test 3: Dynamic Lens Flares
    print("Selecting Dynamic Lens Flares...")
    slot1_select.select_option('dynamic-lens-flares')
    time.sleep(1)
    page.screenshot(path="dynamic_lens_flares_verification.png")
    print("Screenshot saved: dynamic_lens_flares_verification.png")

    # Test 4: Datamosh Brush
    print("Selecting Datamosh Brush...")
    slot1_select.select_option('datamosh-brush')
    time.sleep(1)
    page.screenshot(path="datamosh_brush_verification.png")
    print("Screenshot saved: datamosh_brush_verification.png")

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
                    createShaderModule: () => ({
                        getCompilationInfo: async () => ({ messages: [] })
                    }),
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
