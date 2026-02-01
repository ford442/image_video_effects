from playwright.sync_api import sync_playwright, expect

def verify_shaders_listed(page):
    print("Navigating to app...")
    page.goto("http://localhost:3000")

    print("Waiting for page title...")
    expect(page).to_have_title("Pixelocity")

    page.wait_for_timeout(3000)

    print("Checking dropdown for shaders...")

    slot1_select = page.locator(".stack-slot select").first

    # Check for 'Zipper Reveal' option
    print("Checking for Zipper Reveal option...")
    expect(slot1_select).to_contain_text("Zipper Reveal")

    # Check for 'Xerox Degrade' option
    print("Checking for Xerox Degrade option...")
    expect(slot1_select).to_contain_text("Xerox Degrade")

    print("Taking screenshot...")
    page.screenshot(path="verification/shader_list.png")

if __name__ == "__main__":
    with sync_playwright() as p:
        # Try to enable WebGPU
        browser = p.chromium.launch(
            headless=True,
            args=[
                "--enable-unsafe-webgpu",
                "--use-gl=swiftshader", # or angle
                "--enable-features=Vulkan"
            ]
        )
        page = browser.new_page()
        try:
            verify_shaders_listed(page)
            print("Verification successful!")
        except Exception as e:
            print(f"Verification failed: {e}")
            page.screenshot(path="verification/error.png")
        finally:
            browser.close()
