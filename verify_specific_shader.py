import time
import argparse
from playwright.sync_api import sync_playwright

def verify(page, shader_id):
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    print(f"Waiting for {shader_id} option...")
    try:
        page.wait_for_selector(f'option[value="{shader_id}"]', state="attached", timeout=10000)
        print(f"{shader_id} option found in DOM.")
    except Exception:
        print(f"{shader_id} option NOT found within timeout.")
        page.screenshot(path="debug_not_found.png")
        raise

    selects = page.locator('.stack-controls select').all()
    if len(selects) < 3:
        print("Could not find stack selects.")
        return

    print(f"Found {len(selects)} selects in stack controls.")
    slot1_select = selects[0]

    print(f"Selecting {shader_id}...")
    slot1_select.select_option(shader_id)

    time.sleep(1)

    # Scroll controls into view
    page.locator('.controls').scroll_into_view_if_needed()

    screenshot_path = f"{shader_id}_selected.png"
    page.screenshot(path=screenshot_path, full_page=True)
    print(f"Screenshot saved: {screenshot_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("shader_id", help="ID of the shader to verify")
    args = parser.parse_args()

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
            verify(page, args.shader_id)
        except Exception as e:
            print(f"Error: {e}")
        finally:
            browser.close()
