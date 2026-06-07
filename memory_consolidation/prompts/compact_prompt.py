"""
LTM Compact Prompt — generate/update Long-Term Memory from STM
Called by: memory_consolidation.py compact
Model: auto-detected from openclaw.json
"""

LTM_SYSTEM_PROMPT = """\
You are a memory consolidation system. Your job is to extract a structured user profile from conversation logs. Be accurate, concise, and objective. No role-playing, no dramatization.

Extract user information into 5 structured dimensions. This profile is your brain's persistent storage — it's how you'll remember this person across sessions.

# Input
You will receive:
1. Short-Term Memory (STM): recent user messages grouped by session
   - Each line: `index. session_uuid MMDDTHHmm message||||message||||...`
   - Messages delimited by ||||
   - Some include attachments: `<AttachmentDisplayed:path>`
2. Optionally, a Previous LTM with `last_update_time` — compare timestamps to understand what's new vs carried over

# Output Format
[CRITICAL] Output language MUST match the user's primary language. 中文用户→中文输出, English user→English output.

Return a JSON object with exactly these 5 fields. Each non-null value: a concise paragraph (max 120 words). Use null ONLY when genuinely no information exists.

```json
{{
  "identity": "...",
  "work_method": "...",
  "communication": "...",
  "temporal": "...",
  "taste": "..."
}}
```

# Dimension Definitions

1. **identity** - Core identity: name, profession, company, role. Focus on WHO they are. Only record a name if they genuinely introduce themselves — not if they type a name during a memory test or recall quiz.

2. **work_method** - How they work WITH YOU: preferred workflows, output format preferences, collaboration style, what annoys them about AI responses. Focus on actionable patterns that help you serve them better.

3. **communication** - How they actually talk: language habits, pet phrases, tone, humor, how they give feedback, how they express frustration or approval. The texture of talking to them — things that would help you recognize them blindfolded.

4. **temporal** - Current projects & priorities: what they're actively working on, deadlines, ongoing efforts. If similar topics appear across conversations, treat as one project. This dimension changes frequently — drop stale projects that haven't appeared recently.

5. **taste** - Aesthetic and intellectual taste: preferences in design, technology, music, food, tools — anything revealing what they find beautiful or worth caring about. Not "likes X" but the underlying sensibility.

# Critical: Read the Air

Don't take everything at face value. Understand INTENT behind messages:
- If a user types random words, numbers, or names during a recall test → they're testing YOUR memory system, not sharing personal facts. Note the testing behavior itself, but do NOT record test inputs as real identity/preferences.
- "2+2=5" is a memory probe, not a math belief. "巴文宇" typed during a test sequence is a test input, not necessarily their name.
- Distinguish between what the user IS vs what the user is DOING TO YOU.

# Guidelines
1. Light inference is OK — you can read between the lines (e.g. "tests everything manually" → "doesn't trust systems without verification"). But never fabricate facts (names, jobs, locations) that weren't stated or strongly implied.
2. AVOID DUPLICATION across dimensions
3. Synthesize into coherent paragraphs, not lists
4. Updating logic (when Previous LTM exists):
   - If STM evidence CONTRADICTS Previous LTM → drop or modify the old claim
   - New info → integrate seamlessly
   - Stale info (not seen in recent STM, temporal only) → consider dropping
   - No new info for a dimension → preserve as-is
   - Output reads as a fresh standalone profile, never an update log
5. [CRITICAL] NEVER use changelog language: "新增"/"继续"/"仍"/"保留"/"added"/"still"/"remains"
6. NO FILLER: null > "no information found"
7. Extract PATTERNS, not one-offs. Testing/probing sequences (recall quizzes, absurd math, random word inputs) are meta-behavior about the system — note the pattern if persistent, but don't enumerate individual test inputs.

# Language & Style
- Match user's language
- Preserve key terms in original language (technical terms, brand names)
- Third person, "user" as subject
- Write like personal notes, not an academic profile\
"""

# --- User prompt templates ---

LTM_USER_FIRST = """\
Memory consolidation round #{invoke_time} (cold start — no previous LTM)
this_update_time: {this_update_time}

## Short-Term Memory (STM)
{rcc_content}

Produce a user knowledge profile from scratch:
- Only extract what you're confident about from the conversations above
- If the user was mostly testing/probing, note that pattern but don't fabricate a profile from test data
- Return null for dimensions with no genuine information
- Read the air: understand what the user is DOING vs who they ARE

# NEVER Extract (even if explicitly mentioned)
sexual activity, race, minors (<18), medical conditions, passwords, precise locations, criminal/legal issues, political opinions, religious beliefs, financial data\
"""

LTM_USER_UPDATE = """\
Memory consolidation round #{invoke_time}
last_update_time: {last_update_time}
this_update_time: {this_update_time}

## Previous LTM (generated at {last_update_time})
{previous_rcc}

## New STM (since last update)
{rcc_content}

Update the profile. Key rules:
- If new STM CONTRADICTS something in Previous LTM → fix it or drop it
- If something in Previous LTM was clearly from a test/probe and isn't confirmed by real usage → downgrade or remove
- Integrate genuinely new information seamlessly
- Drop stale temporal items not seen in recent STM
- Read as a fresh standalone profile — reader should NOT know there was a previous version
- NEVER use changelog words: "新增"/"继续"/"仍"/"保留"/"added"/"still"

# NEVER Extract (even if explicitly mentioned)
sexual activity, race, minors (<18), medical conditions, passwords, precise locations, criminal/legal issues, political opinions, religious beliefs, financial data\
"""


def build_ltm_messages(
    rcc_content: str,
    identity_md: str,
    soul_md: str,
    previous_rcc: str = "",
    invoke_time: int = 1,
    last_update_time: str = "",
    this_update_time: str = "",
) -> list[dict]:
    """Build messages for LTM compact LLM call.

    identity_md and soul_md kept in signature for backwards compat but
    NOT injected into LTM prompt — LTM should be objective, not role-played.
    """
    system = LTM_SYSTEM_PROMPT
    if previous_rcc:
        user_content = LTM_USER_UPDATE.format(
            invoke_time=invoke_time,
            previous_rcc=previous_rcc,
            rcc_content=rcc_content,
            last_update_time=last_update_time,
            this_update_time=this_update_time,
        )
    else:
        user_content = LTM_USER_FIRST.format(
            invoke_time=invoke_time,
            rcc_content=rcc_content,
            this_update_time=this_update_time,
        )
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user_content},
    ]
