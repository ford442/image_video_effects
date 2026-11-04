"""Let `cd storage_manager && python -m pytest` resolve `import storage_manager.*`.

The suites import the package by name, which only works with the repo root on
sys.path (running pytest from the root does that; running it from here did not).
"""
import sys
from pathlib import Path

_ROOT = str(Path(__file__).resolve().parent.parent)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
