from playwright.sync_api import sync_playwright
import time

def verify_shaders():
    with sync_playwright() as p:
        # Launch with WebGPU flag as per memory
        browser = p.chromium.launch(
            headless=True,
            args=["--enable-unsafe-webgpu"]
        )
        page = browser.new_page()

        try:
            print("Navigating to app...")
            page.goto("http://localhost:3000")

            # Wait for app to load.
            print("Waiting for controls...")
            # We assume there is a select element for the modes
            page.wait_for_selector("select", timeout=30000)

            # Give it a moment to render
            time.sleep(2)

            # Get content
            content = page.content()

            # Check for strings
            found_rorschach = "Rorschach Inkblot" in content
            found_xray = "X-Ray Reveal" in content

            if found_rorschach:
                print("SUCCESS: Found 'Rorschach Inkblot'")
            else:
                print("FAILURE: 'Rorschach Inkblot' not found")

            if found_xray:
                print("SUCCESS: Found 'X-Ray Reveal'")
            else:
                print("FAILURE: 'X-Ray Reveal' not found")

            # Take screenshot
            page.screenshot(path="verification/verification.png")

        except Exception as e:
            print(f"Error: {e}")
            page.screenshot(path="verification/error.png")
        finally:
            browser.close()

if __name__ == "__main__":
    verify_shaders()
