
import sys
import os
from playwright.sync_api import sync_playwright

def verify_generative_mode(page):
    # 1. Inject WebGPU Mock
    # We need a mock that passes Renderer.ts init() checks:
    # - navigator.gpu.requestAdapter() returns an object with 'features' and 'limits'
    # - adapter.requestDevice() returns a device
    # - canvas.getContext('webgpu') returns a context with configure()

    mock_script = """
    const mockAdapter = {
        features: { has: () => true },
        limits: {
            maxBufferSize: 268435456,
            maxStorageBufferBindingSize: 268435456,
            maxTextureDimension2D: 8192
        },
        requestDevice: async () => ({
            queue: {
                writeBuffer: () => {},
                submit: () => {},
                copyExternalImageToTexture: () => {},
                writeTexture: () => {}
            },
            createShaderModule: () => ({}),
            createRenderPipelineAsync: async () => ({
                getBindGroupLayout: () => ({})
            }),
            createComputePipelineAsync: async () => ({
                getBindGroupLayout: () => ({})
            }),
            createBindGroupLayout: () => ({}),
            createPipelineLayout: () => ({}),
            createBindGroup: () => ({}),
            createSampler: () => ({}),
            createBuffer: () => ({}),
            createTexture: () => ({
                createView: () => ({}),
                destroy: () => {}
            }),
            createCommandEncoder: () => ({
                beginRenderPass: () => ({
                    setPipeline: () => {},
                    setBindGroup: () => {},
                    draw: () => {},
                    end: () => {}
                }),
                beginComputePass: () => ({
                    setPipeline: () => {},
                    setBindGroup: () => {},
                    dispatchWorkgroups: () => {},
                    end: () => {}
                }),
                finish: () => {},
                copyTextureToTexture: () => {}
            }),
            destroy: () => {}
        })
    };

    const mockContext = {
        configure: () => {},
        getCurrentTexture: () => ({ createView: () => ({}) }),
        canvas: { width: 100, height: 100 }
    };

    // Override navigator.gpu
    Object.defineProperty(navigator, 'gpu', {
        value: {
            requestAdapter: async () => mockAdapter,
            getPreferredCanvasFormat: () => 'rgba8unorm'
        },
        writable: true
    });

    // Override getContext
    const originalGetContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(type) {
        if (type === 'webgpu') return mockContext;
        return originalGetContext.apply(this, arguments);
    };
    """

    page.add_init_script(mock_script)

    # 2. Go to App
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    # Wait for controls to load
    page.wait_for_selector(".controls")

    # 3. Click 'Generative' Radio Button
    print("Clicking Generative...")
    # Using the value attribute to be precise
    page.click("input[value='generative']")

    # 4. Wait a moment to see if it springs back
    page.wait_for_timeout(2000)

    # 5. Check if it is still checked
    is_checked = page.is_checked("input[value='generative']")
    print(f"Is Generative checked? {is_checked}")

    if not is_checked:
        print("FAILURE: Radio button sprang back!")
        sys.exit(1)

    # 6. Check if category select also switched to 'Procedural Generation' (value='shader')
    category_value = page.eval_on_selector("#category-select", "el => el.value")
    print(f"Category value: {category_value}")

    if category_value != 'shader':
        print("FAILURE: Category did not switch to 'shader'!")
        sys.exit(1)

    # 7. Take Screenshot
    os.makedirs("verification", exist_ok=True)
    screenshot_path = "verification/generative_fix.png"
    page.screenshot(path=screenshot_path)
    print(f"Screenshot saved to {screenshot_path}")

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    try:
        verify_generative_mode(page)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        browser.close()
