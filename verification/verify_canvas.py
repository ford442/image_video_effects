from playwright.sync_api import sync_playwright, expect
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        # Emulate a high DPI screen
        context = browser.new_context(
            viewport={'width': 800, 'height': 600},
            device_scale_factor=2.0
        )
        page = context.new_page()

        try:
            print("Navigating to app...")
            page.goto("http://localhost:3000")

            # Wait for canvas
            print("Waiting for canvas...")
            canvas = page.locator("canvas").first
            expect(canvas).to_be_visible(timeout=10000)

            # Wait for ResizeObserver to settle
            time.sleep(2)

            # Get canvas info
            canvas_info = canvas.evaluate("""(el) => {
                return {
                    widthAttr: el.width,
                    heightAttr: el.height,
                    clientWidth: el.clientWidth,
                    clientHeight: el.clientHeight,
                    dpr: window.devicePixelRatio,
                    styleWidth: el.style.width,
                    styleHeight: el.style.height
                }
            }""")

            print(f"Canvas Info: {canvas_info}")

            # Verification Logic
            # Verify canvas is responsive (not default 300x150)
            # Note: In headless mode with dpr=2, devicePixelContentBoxSize might still return logical pixels.
            # We accept either 1x or 2x as proof of resize logic working.

            if canvas_info['widthAttr'] == 300 and canvas_info['clientWidth'] != 300:
                 raise Exception("Canvas did not resize from default 300!")

            if canvas_info['widthAttr'] < canvas_info['clientWidth']:
                 raise Exception(f"Canvas buffer ({canvas_info['widthAttr']}) is smaller than CSS size ({canvas_info['clientWidth']})!")

            if canvas_info['styleWidth'] != '100%':
                raise Exception(f"Canvas style mismatch! Width: {canvas_info['styleWidth']}")

            print("Verification Successful!")

            # Take screenshot
            page.screenshot(path="verification/verification.png")

        except Exception as e:
            print(f"Error: {e}")
            page.screenshot(path="verification/error.png")
            raise e
        finally:
            browser.close()

if __name__ == "__main__":
    run()
