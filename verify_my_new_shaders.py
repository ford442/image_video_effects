import time
from playwright.sync_api import sync_playwright, Page, expect

def test_new_shaders(page: Page):
    # Mock WebGPU before loading the page
    page.add_init_script("""
    const mockDevice = {
        queue: {
            submit: () => {},
            writeBuffer: () => {},
            writeTexture: () => {},
            copyExternalImageToTexture: () => {},
        },
        createCommandEncoder: () => ({
            beginComputePass: () => ({
                setPipeline: () => {},
                setBindGroup: () => {},
                dispatchWorkgroups: () => {},
                end: () => {},
            }),
            beginRenderPass: () => ({
                setPipeline: () => {},
                setBindGroup: () => {},
                setVertexBuffer: () => {},
                setIndexBuffer: () => {},
                draw: () => {},
                end: () => {},
            }),
            finish: () => ({}),
            copyTextureToTexture: () => {},
        }),
        createBindGroup: () => ({}),
        createBindGroupLayout: () => ({}),
        createPipelineLayout: () => ({}),
        createShaderModule: () => ({}),
        createRenderPipelineAsync: async () => ({
            getBindGroupLayout: () => ({}),
        }),
        createComputePipelineAsync: async () => ({
            getBindGroupLayout: () => ({}),
        }),
        createBuffer: () => ({
            destroy: () => {},
        }),
        createTexture: () => ({
            createView: () => ({}),
            destroy: () => {},
        }),
        createSampler: () => ({}),
        destroy: () => {},
        features: {
            has: (feature) => true, // Mock all features as supported
        },
    };

    const mockAdapter = {
        requestDevice: async () => mockDevice,
        features: {
            has: (feature) => true,
        },
    };

    // Inject navigator.gpu
    Object.defineProperty(navigator, 'gpu', {
        writable: true,
        value: {
            requestAdapter: async () => mockAdapter,
            getPreferredCanvasFormat: () => 'bgra8unorm',
        },
    });

    // Inject canvas context for WebGPU
    const getContextOriginal = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (type) {
        if (type === 'webgpu') {
            return {
                configure: () => {},
                getCurrentTexture: () => ({
                    createView: () => ({}),
                }),
            };
        }
        return getContextOriginal.apply(this, arguments);
    };
    """)

    print("Navigating to app...")
    page.goto("http://localhost:3000")

    # Wait for the canvas to ensure app loaded
    page.wait_for_selector("canvas", state="visible", timeout=10000)
    print("Canvas found.")

    # Wait for controls to appear
    page.wait_for_selector("select", state="attached")

    # Wait a bit for the shader list to populate asynchronously
    time.sleep(2)

    # Get all options from the select
    options = page.eval_on_selector_all("option", "elements => elements.map(e => e.text)")
    print(f"Found {len(options)} options.")

    if "Pixel Rain" in options:
        print("SUCCESS: 'Pixel Rain' found in options.")
    else:
        print("FAILURE: 'Pixel Rain' NOT found in options.")

    if "Vortex Warp" in options:
        print("SUCCESS: 'Vortex Warp' found in options.")
    else:
        print("FAILURE: 'Vortex Warp' NOT found in options.")

    # Attempt to select and check parameters
    try:
        # Check Pixel Rain params
        page.select_option("select:has(option[value='pixel-rain'])", "pixel-rain")
        print("Selected Pixel Rain")
        time.sleep(1)
        if "Rain Speed" in page.content():
             print("SUCCESS: 'Rain Speed' parameter found.")
        else:
             print("FAILURE: 'Rain Speed' parameter NOT found.")
        page.screenshot(path="verification/pixel_rain_selected.png", full_page=True)

        # Check Vortex Warp params
        page.select_option("select:has(option[value='vortex-warp'])", "vortex-warp")
        print("Selected Vortex Warp")
        time.sleep(1)
        if "Twist Factor" in page.content():
             print("SUCCESS: 'Twist Factor' parameter found.")
        else:
             print("FAILURE: 'Twist Factor' parameter NOT found.")
        page.screenshot(path="verification/vortex_warp_selected.png", full_page=True)

    except Exception as e:
        print(f"Error selecting option: {e}")

if __name__ == "__main__":
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        page = context.new_page()
        try:
            test_new_shaders(page)
        except Exception as e:
            print(f"Test failed: {e}")
        finally:
            browser.close()
