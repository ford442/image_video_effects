with open("src/App.tsx", "r") as f:
    text = f.read()

# Fix the stray `); // eslint-disable-next-line react-hooks/exhaustive-deps` on line 409
import re
text = re.sub(r'\s*\);\s*//\s*eslint-disable-next-line\s*react-hooks/exhaustive-deps\n\s*},\s*\[shaderCategory\]\);', '\n    }, [shaderCategory]);', text)

with open("src/App.tsx", "w") as f:
    f.write(text)
