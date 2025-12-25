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

    # Select the "Image" filter category if necessary (though shaders should be in default list or categorized)
    # The memory says Controls.tsx has an 'Effect Filter'. Let's find it.

    # Wait for controls to appear
    page.wait_for_selector("select", state="attached")

    # The first select is typically the filter category in the sidebar
    # Let's inspect the page content for "Velvet Vortex" in the shader dropdown

    # We need to find the "Slot 1" dropdown.
    # It usually has options like "None", "Liquid Metal", etc.

    # Let's try to locate the select element that contains "Velvet Vortex"
    # Wait a bit for the shader list to populate asynchronously
    time.sleep(2)

    # Look for the option in the DOM
    # Note: options might not be visible until clicked, but they exist in the DOM

    # Check if "Velvet Vortex" is in the page source
    content = page.content()
    if "Velvet Vortex" in content:
        print("SUCCESS: 'Velvet Vortex' found in page content.")
    else:
        print("FAILURE: 'Velvet Vortex' NOT found in page content.")

    if "Neon Echo" in content:
        print("SUCCESS: 'Neon Echo' found in page content.")
    else:
        print("FAILURE: 'Neon Echo' NOT found in page content.")

    # Try to select it to see parameters
    # The first select after the filter is usually Slot 1
    # Or we can search for the select that contains the option

    try:
        # Find the select element that has the option "velvet-vortex"
        # We need to click the sidebar toggle if controls are hidden?
        # Memory says controls are in a sidebar <aside>.

        # Take a screenshot of the initial state
        page.screenshot(path="/home/jules/verification/initial_load.png")

        # Try to select the option
        page.select_option("select:has(option[value='velvet-vortex'])", "velvet-vortex")
        print("Selected Velvet Vortex")

        # Wait for parameters to update
        time.sleep(1)

        # Check for specific parameter labels
        if "Vortex Radius" in page.content():
             print("SUCCESS: 'Vortex Radius' parameter found.")
        else:
             print("FAILURE: 'Vortex Radius' parameter NOT found.")

        page.screenshot(path="/home/jules/verification/velvet_vortex_selected.png")

    except Exception as e:
        print(f"Error selecting option: {e}")
        page.screenshot(path="/home/jules/verification/error.png")

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
