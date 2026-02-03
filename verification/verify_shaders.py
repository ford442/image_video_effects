from playwright.sync_api import sync_playwright
import time

def verify_shaders():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=['--enable-unsafe-webgpu'])
        page = browser.new_page()

        print("Navigating to app...")
        page.goto("http://localhost:3000")

        # Wait for the app to load
        print("Waiting for controls...")
        try:
            page.wait_for_selector(".controls", timeout=10000)
            # Wait a bit more for shaders to fetch
            time.sleep(2)
        except Exception as e:
            print(f"Error waiting for controls: {e}")
            page.screenshot(path="verification/error.png")
            return

        print("Checking for new shaders...")
        content = page.content()

        shaders = [
            "Lichtenberg Fractal",
            "Encaustic Wax",
            "Aerogel Smoke",
            "Cymatic Sand"
        ]

        all_found = True
        for shader in shaders:
            if shader in content:
                print(f"✅ Found {shader}")
            else:
                print(f"❌ Missing {shader}")
                # Try checking the other category
                # The dropdown filters by category, so we might need to switch category to see some
                # But the <option> elements might be in the DOM if the select was rendered?
                # React might unmount the options.
                all_found = False

        # If missing, try switching categories and checking again
        if not all_found:
            print("Switching categories to check again...")
            try:
                # Select 'shader' category (Procedural Generation)
                page.select_option("#category-select", "shader")
                time.sleep(1)
                content_shader = page.content()

                # Select 'image' category (Effects / Filters)
                page.select_option("#category-select", "image")
                time.sleep(1)
                content_image = page.content()

                content = content_shader + content_image

                for shader in shaders:
                    if shader in content:
                        print(f"✅ Found {shader} (after switching)")
                    else:
                        print(f"❌ Still Missing {shader}")
            except Exception as e:
                print(f"Error switching categories: {e}")

        page.screenshot(path="verification/verification.png")
        print("Screenshot saved to verification/verification.png")
        browser.close()

if __name__ == "__main__":
    verify_shaders()
