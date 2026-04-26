with open("src/App.tsx", "r") as f:
    text = f.read()

# Add videoList.length to the dependency array. It seems my previous sed command failed to add it correctly because it missed matching the old array.
# The current array is: }, [videoB3hdMode, inputSource, b3hdSegmentLength, b3hdIntervalSeconds]);

import re
text = re.sub(r'\}, \[videoB3hdMode, inputSource, b3hdSegmentLength, b3hdIntervalSeconds\]\);', r'}, [videoB3hdMode, inputSource, b3hdSegmentLength, b3hdIntervalSeconds, videoList.length]);', text)

with open("src/App.tsx", "w") as f:
    f.write(text)
