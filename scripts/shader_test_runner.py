#!/usr/bin/env python3
"""
Shader Test Runner - Automated WebGPU shader validation
Tests shaders on the deployed site for compilation errors and parameter functionality

Usage:
    python shader_test_runner.py [URL]
    
Examples:
    python shader_test_runner.py
    python shader_test_runner.py https://test.1ink.us/image_video_effects/index.html
    python shader_test_runner.py --headful  # Show browser window
    python shader_test_runner.py --sample 20  # Test only 20 shaders
"""

import asyncio
import json
import sys
import time
from dataclasses import dataclass, asdict
from typing import List, Optional
from pathlib import Path

# Check for playwright
try:
    from playwright.async_api import async_playwright, Page, Browser
except ImportError:
    print("❌ Playwright not installed. Install with:")
    print("   pip install playwright")
    print("   playwright install chromium")
    sys.exit(1)


@dataclass
class ShaderResult:
    name: str
    id: str
    category: str
    status: str  # "pass", "fail", "skip"
    params: int = 0
    params_work: bool = True
    errors: List[str] = None
    
    def __post_init__(self):
        if self.errors is None:
            self.errors = []


@dataclass
class TestReport:
    url: str
    timestamp: str
    duration_seconds: float
    total: int
    passed: int
    failed: int
    skipped: int
    webgpu_supported: bool
    results: List[ShaderResult]
    
    def to_dict(self):
        return {
            **asdict(self),
            'results': [asdict(r) for r in self.results]
        }


class ShaderValidator:
    def __init__(self, url: str, headless: bool = True, sample_size: Optional[int] = None):
        self.url = url
        self.headless = headless
        self.sample_size = sample_size
        self.results: List[ShaderResult] = []
        self.console_errors: List[str] = []
        self.start_time: float = 0
        
    async def setup_browser(self) -> tuple[Browser, Page]:
        """Initialize browser with WebGPU support"""
        playwright = await async_playwright().start()
        
        browser = await playwright.chromium.launch(
            headless=self.headless,
            args=[
                '--enable-webgpu',
                '--enable-features=Vulkan,WebGPU',
                '--disable-web-security',
            ]
        )
        
        context = await browser.new_context(
            viewport={'width': 1280, 'height': 720},
            device_scale_factor=1
        )
        
        page = await context.new_page()
        
        # Collect console errors
        page.on("console", lambda msg: self._handle_console(msg))
        page.on("pageerror", lambda err: self.console_errors.append(str(err)))
        
        return browser, page
    
    def _handle_console(self, msg):
        """Handle console messages"""
        if msg.type == "error":
            self.console_errors.append(msg.text)
    
    async def wait_for_webgpu(self, page: Page) -> bool:
        """Check if WebGPU is available"""
        for _ in range(10):
            has_webgpu = await page.evaluate("() => !!navigator.gpu")
            if has_webgpu:
                return True
            await asyncio.sleep(0.5)
        return False
    
    async def get_shader_list(self, page: Page) -> List[dict]:
        """Extract shader list from page"""
        shaders = await page.evaluate("""() => {
            const shaders = [];
            const selects = document.querySelectorAll('select');
            
            for (const select of selects) {
                if (select.options.length > 5) {
                    for (const option of select.options) {
                        if (option.value && option.text && 
                            !option.value.includes('placeholder') &&
                            !option.disabled) {
                            shaders.push({
                                id: option.value,
                                name: option.text.trim(),
                                category: select.name || select.id || 'unknown'
                            });
                        }
                    }
                }
            }
            
            // Remove duplicates
            return shaders.filter((s, i, arr) => 
                arr.findIndex(t => t.id === s.id) === i
            );
        }""")
        
        return shaders
    
    async def test_shader(self, page: Page, shader: dict, index: int, total: int) -> ShaderResult:
        """Test a single shader"""
        prefix = f"[{index + 1}/{total}]"
        
        # Clear errors
        self.console_errors.clear()
        prev_errors = len(self.console_errors)
        
        try:
            # Select shader
            selected = await page.evaluate("""(shaderId) => {
                const selects = document.querySelectorAll('select');
                for (const select of selects) {
                    if (select.options.length > 5) {
                        const option = Array.from(select.options).find(o => 
                            o.value === shaderId || o.text.includes(shaderId)
                        );
                        if (option) {
                            select.value = option.value;
                            select.dispatchEvent(new Event('change', { bubbles: true }));
                            return true;
                        }
                    }
                }
                return false;
            }""", shader['id'])
            
            if not selected:
                return ShaderResult(
                    name=shader['name'],
                    id=shader['id'],
                    category=shader['category'],
                    status="skip",
                    errors=["Could not select shader"]
                )
            
            # Wait for compilation
            await asyncio.sleep(2)
            
            # Check for errors
            shader_errors = [e for e in self.console_errors[prev_errors:] if any(
                keyword in e.lower() for keyword in 
                ['shader', 'webgpu', 'pipeline', 'compilation', 'wgsl', 'compute']
            )]
            
            if shader_errors:
                return ShaderResult(
                    name=shader['name'],
                    id=shader['id'],
                    category=shader['category'],
                    status="fail",
                    errors=shader_errors[:3]
                )
            
            # Check parameters
            param_info = await page.evaluate("""() => {
                const sliders = document.querySelectorAll('input[type="range"]');
                const params = [];
                
                for (const slider of sliders) {
                    const val = parseFloat(slider.value);
                    const min = parseFloat(slider.min) || 0;
                    const max = parseFloat(slider.max) || 1;
                    
                    params.push({
                        name: slider.name || slider.id || 'unnamed',
                        value: val,
                        inRange: val >= min && val <= max
                    });
                    
                    // Test setting
                    const testVal = min + (max - min) * 0.6;
                    slider.value = testVal;
                    slider.dispatchEvent(new Event('input', { bubbles: true }));
                }
                
                return {
                    count: sliders.length,
                    allInRange: params.every(p => p.inRange),
                    params: params
                };
            }""")
            
            await asyncio.sleep(0.3)
            
            return ShaderResult(
                name=shader['name'],
                id=shader['id'],
                category=shader['category'],
                status="pass",
                params=param_info['count'],
                params_work=param_info['allInRange']
            )
            
        except Exception as e:
            return ShaderResult(
                name=shader['name'],
                id=shader['id'],
                category=shader['category'],
                status="fail",
                errors=[str(e)]
            )
    
    async def run(self) -> TestReport:
        """Run full validation"""
        self.start_time = time.time()
        
        print("🚀 Shader Test Runner")
        print(f"📍 URL: {self.url}")
        print(f"🖥️  Headless: {self.headless}")
        print("")
        
        browser, page = await self.setup_browser()
        
        try:
            # Load page
            print("⏳ Loading page...")
            await page.goto(self.url, wait_until="networkidle", timeout=60000)
            await asyncio.sleep(3)
            
            # Check WebGPU
            print("🔍 Checking WebGPU support...")
            has_webgpu = await self.wait_for_webgpu(page)
            
            if not has_webgpu:
                print("❌ WebGPU not available!")
                return TestReport(
                    url=self.url,
                    timestamp=time.strftime("%Y-%m-%d %H:%M:%S"),
                    duration_seconds=0,
                    total=0, passed=0, failed=0, skipped=0,
                    webgpu_supported=False,
                    results=[]
                )
            
            print("✅ WebGPU supported")
            print("")
            
            # Get shaders
            print("📋 Fetching shader list...")
            shaders = await self.get_shader_list(page)
            
            if self.sample_size:
                shaders = shaders[:self.sample_size]
            
            print(f"📝 Found {len(shaders)} shaders to test")
            print("")
            
            # Test shaders
            print("🧪 Testing shaders...")
            print("")
            
            for i, shader in enumerate(shaders):
                result = await self.test_shader(page, shader, i, len(shaders))
                self.results.append(result)
                
                icon = "✅" if result.status == "pass" else "❌" if result.status == "fail" else "⚠️"
                param_str = f"({result.params} params)" if result.params > 0 else ""
                print(f"[{i + 1}/{len(shaders)}] {icon} {result.name} {param_str}")
                
                if result.errors:
                    for err in result.errors[:2]:
                        print(f"      → {err[:80]}")
            
            # Calculate summary
            duration = time.time() - self.start_time
            passed = len([r for r in self.results if r.status == "pass"])
            failed = len([r for r in self.results if r.status == "fail"])
            skipped = len([r for r in self.results if r.status == "skip"])
            
            report = TestReport(
                url=self.url,
                timestamp=time.strftime("%Y-%m-%d %H:%M:%S"),
                duration_seconds=duration,
                total=len(shaders),
                passed=passed,
                failed=failed,
                skipped=skipped,
                webgpu_supported=True,
                results=self.results
            )
            
            return report
            
        finally:
            await browser.close()
    
    def print_report(self, report: TestReport):
        """Print formatted report"""
        print("\n" + "=" * 60)
        print("📊 TEST SUMMARY")
        print("=" * 60)
        print(f"URL: {report.url}")
        print(f"Duration: {report.duration_seconds:.1f}s")
        print(f"WebGPU: {'✅ Supported' if report.webgpu_supported else '❌ Not Available'}")
        print("")
        print(f"Total: {report.total}")
        print(f"✅ Passed: {report.passed}")
        print(f"❌ Failed: {report.failed}")
        print(f"⚠️  Skipped: {report.skipped}")
        print("=" * 60)
        
        if report.failed > 0:
            print("\n❌ FAILED SHADERS:")
            print("-" * 60)
            for r in report.results:
                if r.status == "fail":
                    print(f"\n• {r.name} ({r.category})")
                    for err in r.errors[:2]:
                        print(f"  → {err[:100]}")
        
        # Save report
        report_path = Path(__file__).parent / "shader-test-report.json"
        with open(report_path, 'w') as f:
            json.dump(report.to_dict(), f, indent=2)
        
        print(f"\n💾 Report saved to: {report_path}")


def main():
    url = "https://test.1ink.us/image_video_effects/index.html"
    headless = True
    sample_size = None
    
    # Parse arguments
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == '--headful':
            headless = False
        elif arg == '--sample' and i + 1 < len(args):
            sample_size = int(args[i + 1])
            i += 1
        elif not arg.startswith('--'):
            url = arg
        i += 1
    
    # Run tests
    validator = ShaderValidator(url, headless=headless, sample_size=sample_size)
    
    try:
        report = asyncio.run(validator.run())
        validator.print_report(report)
        
        # Exit with error code if failures
        if report.failed > 0:
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n\n⚠️  Testing interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
