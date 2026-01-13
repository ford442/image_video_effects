import time
from playwright.sync_api import sync_playwright

def verify(page):
    page.on("console", lambda msg: print(f"Browser console: {msg.text}"))
    page.on("pageerror", lambda exc: print(f"Browser error: {exc}"))

    print("Navigating to app...")
    page.goto("http://localhost:3000")

    print("Waiting for Neon Fluid Warp option...")
    try:
        page.wait_for_selector('option[value="neon-fluid-warp"]', state="attached", timeout=10000)
        print("Neon Fluid Warp option found in DOM.")
    except Exception:
        print("Neon Fluid Warp option NOT found within timeout.")
        page.screenshot(path="verification/debug_not_found.png", full_page=True)
        raise

    selects = page.locator('.stack-controls select').all()
    if len(selects) < 3:
        print("Could not find stack selects.")
        pass

    print(f"Found {len(selects)} selects in stack controls.")
    slot1_select = selects[0]

    print("Selecting Neon Fluid Warp...")
    slot1_select.select_option('neon-fluid-warp')

    time.sleep(2)

    controls = page.locator('.sidebar')
    if controls.count() > 0:
        controls.screenshot(path="verification/neon_fluid_warp_selected.png")
        print("Screenshot saved: neon_fluid_warp_selected.png")
    else:
        page.screenshot(path="verification/neon_fluid_warp_selected_full.png", full_page=True)
        print("Sidebar not found, took full page screenshot.")

    print("Selecting Magnetic Luma Sort...")
    slot1_select.select_option('magnetic-luma-sort')
    time.sleep(2)

    if controls.count() > 0:
        controls.screenshot(path="verification/magnetic_luma_sort_selected.png")
        print("Screenshot saved: magnetic_luma_sort_selected.png")
    else:
        page.screenshot(path="verification/magnetic_luma_sort_selected_full.png", full_page=True)

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
                    createSampler: () => {},
                    destroy: () => {}
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
