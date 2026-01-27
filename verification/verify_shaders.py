from playwright.sync_api import sync_playwright, expect

def run(playwright):
    print("Launching browser...")
    browser = playwright.chromium.launch(headless=True, args=["--enable-unsafe-webgpu", "--use-gl=swiftshader"])
    page = browser.new_page()
    print("Navigating to app...")
    try:
        page.goto("http://localhost:3000")
    except Exception as e:
        print(f"Error navigating: {e}")
        browser.close()
        return

    print("Checking title...")
    expect(page).to_have_title("Pixelocity")

    print("Selecting category...")
    # Select Category "Effects / Filters" (value="image")
    page.select_option("select#category-select", "image")

    # Wait a bit for the list to update if needed
    page.wait_for_timeout(1000)

    print("Checking for new shaders...")
    # Check if options exist in the select
    biomimetic = page.locator("option[value='biomimetic-scales']").first
    cmyk = page.locator("option[value='cmyk-halftone-interactive']").first

    expect(biomimetic).to_be_attached()
    print("Biomimetic Scales found.")
    expect(cmyk).to_be_attached()
    print("CMYK Halftone found.")

    # Select one of them
    print("Selecting Biomimetic Scales...")
    slot1_select = page.locator(".stack-slot select").first
    slot1_select.select_option("biomimetic-scales")

    page.wait_for_timeout(2000)

    print("Taking screenshot...")
    page.screenshot(path="verification/verification.png")

    browser.close()
    print("Done.")

if __name__ == "__main__":
    with sync_playwright() as playwright:
        run(playwright)
