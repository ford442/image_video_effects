import time
import json
from playwright.sync_api import sync_playwright

def verify(page):
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    # Check if we can fetch the JSON list
    print("Checking JSON availability...")
    response = page.request.get("http://localhost:3000/shader-lists/interactive-mouse.json")
    if response.ok:
        data = response.json()
        ids = [x['id'] for x in data]
        print(f"Server returned {len(ids)} shaders in interactive-mouse.json")
        if "quantized-ripples" in ids:
            print("PASS: quantized-ripples is in the JSON served by the server.")
        else:
            print("FAIL: quantized-ripples is NOT in the JSON served by the server.")
    else:
        print(f"FAIL: Could not fetch JSON list. Status: {response.status}")

    # Wait for the select element
    try:
        page.wait_for_selector('.stack-controls select', state="attached", timeout=10000)
        print("Stack controls found.")
    except:
        print("Stack controls not found. App might have crashed.")
        page.screenshot(path="/home/jules/verification/crash_debug.png")
        return

    # Wait a bit for async load
    time.sleep(3)

    # Change category to 'image'
    page.select_option('#category-select', 'image')
    time.sleep(1)

    # Inspect options in the first select
    select = page.locator('.stack-controls select').first
    options = select.locator('option').all_inner_texts()
    values = select.locator('option').all_get_attributes('value')

    print(f"Found {len(options)} options in dropdown.")

    new_shaders = [
        "quantized-ripples",
        "digital-mold",
        "refractive-bubbles",
        "chroma-shift-grid"
    ]

    missing = []
    for shader in new_shaders:
        if shader in values:
            print(f"Found {shader}")
        else:
            missing.append(shader)

    if missing:
        print(f"Missing shaders: {missing}")
        print("First 10 options available:", values[:10])
    else:
        print("ALL NEW SHADERS FOUND IN UI.")

    page.screenshot(path="/home/jules/verification/debug_ui.png")

if __name__ == "__main__":
    with sync_playwright() as p:
        print("Launching browser...")
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Listen to console
        page.on("console", lambda msg: print(f"Browser Console: {msg.text}"))
        page.on("pageerror", lambda exc: print(f"Browser Error: {exc}"))

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
