from playwright.sync_api import sync_playwright

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        try:
            # Inject a mock for WebGPU to prevent crash if possible, or just expect the UI to load controls
            # Note: The app might fail to render canvas but controls are React.

            # Simple mock to prevent immediate crash if code checks for navigator.gpu
            page.add_init_script("""
                if (!navigator.gpu) {
                    navigator.gpu = {
                        requestAdapter: async () => null,
                    };
                }
            """)

            page.goto("http://localhost:3000")
            page.wait_for_timeout(2000) # Wait for React to mount

            # Take screenshot
            page.screenshot(path="verification.png")
            print("Screenshot taken.")
        except Exception as e:
            print(f"Error: {e}")
        finally:
            browser.close()

if __name__ == "__main__":
    run()
