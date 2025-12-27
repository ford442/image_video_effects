from playwright.sync_api import sync_playwright

def verify_remote_app():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()

        # 1. Open Main App to enable syncing
        main_page = context.new_page()
        print("Navigating to Main App...")
        try:
            main_page.goto("http://localhost:3000/")
            # Wait for main app to load - check for header
            main_page.wait_for_selector(".header", timeout=60000)
            print("Main App loaded.")
        except Exception as e:
            print(f"Failed to load Main App: {e}")
            # Continue anyway, Remote App might still render "LOST CONNECTION" which is verifyable

        # 2. Open Remote App
        remote_page = context.new_page()
        print("Navigating to Remote App...")
        # Set viewport to small height to force scrollbar if content is long enough
        remote_page.set_viewport_size({"width": 400, "height": 400})

        remote_page.goto("http://localhost:3000/?mode=remote")

        # 3. Wait for Remote App to load
        # Check for the new header structure
        try:
            remote_page.wait_for_selector("h2", state="visible", timeout=30000)
            header_text = remote_page.inner_text("h2")
            print(f"Remote Header found: {header_text}")

            if "Remote Control" in header_text:
                print("Connected state verified.")
            elif "LOST CONNECTION" in remote_page.content():
                print("Lost Connection state verified (Main app might not be syncing in headless).")
        except Exception as e:
            print(f"Error waiting for remote app: {e}")

        # 4. Take Screenshot of top
        remote_page.screenshot(path="verification/remote_top.png")
        print("Screenshot saved: verification/remote_top.png")

        # 5. Attempt to scroll down in .remote-content
        # We need to see if scrollbar is present or if we can scroll.
        # The .remote-content div should be scrollable.
        try:
            # Check if .remote-content exists
            if remote_page.locator(".remote-content").count() > 0:
                print("Found .remote-content container.")
                # Evaluate scroll height vs client height
                is_scrollable = remote_page.evaluate("""() => {
                    const el = document.querySelector('.remote-content');
                    return el.scrollHeight > el.clientHeight;
                }""")
                print(f"Is .remote-content scrollable? {is_scrollable}")

                if is_scrollable:
                    # Scroll to bottom
                    remote_page.evaluate("document.querySelector('.remote-content').scrollTop = 1000")
                    remote_page.wait_for_timeout(500) # Wait for scroll
                    remote_page.screenshot(path="verification/remote_bottom.png")
                    print("Screenshot saved: verification/remote_bottom.png")
            else:
                print("Could not find .remote-content (maybe in Lost Connection state).")

        except Exception as e:
            print(f"Error checking scroll: {e}")

        browser.close()

if __name__ == "__main__":
    verify_remote_app()
