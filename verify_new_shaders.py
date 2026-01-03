
import os
from playwright.sync_api import sync_playwright, expect

def check_new_shaders():
    with sync_playwright() as p:
        print("Launching browser...")
        # Mock WebGPU in args if possible, but headless won't have it.
        browser = p.chromium.launch(headless=True, args=['--enable-unsafe-webgpu'])
        page = browser.new_page()

        # Handle console errors
        page.on("console", lambda msg: print(f"Console: {msg.text}"))
        page.on("pageerror", lambda exc: print(f"PageError: {exc}"))

        print("Navigating to app...")
        try:
            page.goto("http://localhost:3000/", timeout=30000)
        except Exception as e:
            print(f"Error navigating: {e}")
            return

        # Wait for controls to load
        try:
            print("Waiting for stack controls...")
            page.wait_for_selector(".stack-controls select", state="attached", timeout=10000)
        except Exception as e:
            print(f"Controls not found: {e}")
            # Take a debug screenshot
            page.screenshot(path="verification_debug.png", full_page=True)
            return

        selects = page.locator(".stack-controls select").all()
        if not selects:
            print("No select elements found in .stack-controls")
            return

        print(f"Found {len(selects)} selects.")

        # Check Shader 1: Circuit Breaker
        target_shader = "circuit-breaker"
        print(f"Looking for {target_shader}...")

        # Get options from the first select
        options = selects[0].locator("option").all_inner_texts()
        # Filter for Circuit Breaker (Name in UI might be "Circuit Breaker")

        found = False
        for opt in options:
            if "Circuit Breaker" in opt:
                found = True
                print("Found 'Circuit Breaker' option!")
                break

        if found:
            selects[0].select_option(label="Circuit Breaker")
            page.wait_for_timeout(1000)
            page.screenshot(path="circuit_breaker_selected.png")
            print("Selected Circuit Breaker and saved screenshot.")
        else:
            print("'Circuit Breaker' not found in options.")
            print(f"First 10 options: {options[:10]}")

        # Check Shader 2: Reality Tear
        target_shader_2 = "reality-tear"
        print(f"Looking for {target_shader_2}...")

        found_2 = False
        options_2 = selects[0].locator("option").all_inner_texts()
        for opt in options_2:
            if "Reality Tear" in opt:
                found_2 = True
                print("Found 'Reality Tear' option!")
                break

        if found_2:
            selects[0].select_option(label="Reality Tear")
            page.wait_for_timeout(1000)
            page.screenshot(path="reality_tear_selected.png")
            print("Selected Reality Tear and saved screenshot.")
        else:
            print("'Reality Tear' not found in options.")

        browser.close()

if __name__ == "__main__":
    check_new_shaders()
