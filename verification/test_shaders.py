from playwright.sync_api import sync_playwright

def run(playwright):
    browser = playwright.chromium.launch(headless=True)
    page = browser.new_page()

    # Listen to console
    page.on("console", lambda msg: print(f"CONSOLE: {msg.text}"))

    # Go to app
    page.goto("http://localhost:3000")

    # Wait for loading
    page.wait_for_timeout(5000)

    # Take screenshot immediately to see state
    page.screenshot(path="verification/verification.png")
    print("Screenshot taken.")

    selects = page.locator('select')
    print(f"Found {selects.count()} selects")

    # Check options of Select 1
    if selects.count() > 1:
        select1 = selects.nth(1)
        opts = select1.locator('option').all()
        vals = [o.get_attribute('value') for o in opts]
        print("Values in Select 1:")
        print(vals)

    browser.close()

with sync_playwright() as playwright:
    run(playwright)
