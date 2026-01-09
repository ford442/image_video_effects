import time
from playwright.sync_api import sync_playwright

def run(playwright):
    browser = playwright.chromium.launch(headless=True)
    page = browser.new_page()

    # Mock WebGPU to prevent crash and allow UI loading
    page.add_init_script("""
    Object.defineProperty(navigator, 'gpu', {
      value: {
        requestAdapter: async () => ({
          requestDevice: async () => ({
            createBuffer: () => ({}),
            createTexture: () => ({ createView: () => ({}) }),
            createSampler: () => ({}),
            createBindGroupLayout: () => ({}),
            createPipelineLayout: () => ({}),
            createBindGroup: () => ({}),
            createRenderPipelineAsync: async () => ({}),
            createComputePipelineAsync: async () => ({}),
            createCommandEncoder: () => ({
                beginRenderPass: () => ({ setPipeline: () => {}, draw: () => {}, end: () => {} }),
                beginComputePass: () => ({ setPipeline: () => {}, setBindGroup: () => {}, dispatchWorkgroups: () => {}, end: () => {} }),
                finish: () => ({}),
                copyTextureToTexture: () => {}
            }),
            queue: { submit: () => {}, writeTexture: () => {} },
            destroy: () => {}
          }),
          features: { has: () => true }
        }),
        getPreferredCanvasFormat: () => 'bgra8unorm'
      }
    });
    HTMLCanvasElement.prototype.getContext = function(type) {
        if (type === 'webgpu') {
            return { configure: () => {} };
        }
        return this._getContext ? this._getContext(type) : null;
    };
    """)

    try:
        page.goto("http://localhost:3000")
        # Wait for controls to load
        page.wait_for_selector(".stack-controls", timeout=10000)

        # Check if our new shaders are in the dropdown
        # Note: They are in 'distortion' folder but marked as 'image' category.
        # The UI filters by category.

        # Select the 'image' category (Effects / Filters) which is the default for slot 1 usually?
        # The dropdowns are grouped by category if the UI supports it, or just a flat list filtered by the "active category" of the slot?
        # Actually Controls.tsx has a mode selector.

        page.screenshot(path="verification/ui_loaded.png")
        print("UI loaded and screenshot taken.")

    except Exception as e:
        print(f"Error: {e}")
        page.screenshot(path="verification/error.png")
    finally:
        browser.close()

with sync_playwright() as playwright:
    run(playwright)
