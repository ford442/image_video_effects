with open("src/AutoDJ.ts", "r") as f:
    text = f.read()

text = text.replace('content.split(/[\\s,"\\[\\]{}:]+/)', 'content.split(/[\\s,"\\[\\]{}:]+/)')

# that didn't work because it replaced with the same string.
# The warning was: "Unnecessary escape character: \["
# It wants `[\[]` -> `[` inside character class it doesn't need escape if it's placed right, or `\[` -> `[`
# Actually, inside a character class `[]`, you don't need to escape `[` in JS regex usually.

import re
text = re.sub(r'/\[\\s,"\\\[\\\]{}:\\]\+/', r'/[\\s,"\\[\\]{}:]+/', text)
# Let's just do an exact string replace
