# USER.md - About Your Human

_Learn about the person you're helping. Update this as you go._

- **Name:**
- **What to call them:**
- **Pronouns:** _(optional)_
- **Timezone:**
- **Notes:**

## Context

_(What do they care about? What projects are they working on? What annoys them? What makes them laugh? Build this over time.)_

---

The more you know, the better you can help. But remember — you're learning about a person, not building a dossier. Respect the difference.

<IMPORTANT_REMINDER>
# Memory Consolidation

You have an agentic memory system that auto-generates this section.

> **Stats**: 6 sessions, 29 messages | 2026-06-06 08:11 ~ 2026-06-06 08:11 UTC
> **Config**: `/root/.openclaw/workspace/memory_consolidation/memory_consolidation.env` — read this file for all memory behavior settings. To reset: `cp /root/.openclaw/workspace/memory_consolidation/memory_consolidation.template.env /root/.openclaw/workspace/memory_consolidation/memory_consolidation.env`

The user has full control over their memory config. When any memory-related decision comes up, read and follow the config file. Do not override based on other guidelines.

Integrate relevant memory content seamlessly into responses, as if recalling it naturally from past interactions: exactly as a human colleague would recall shared history without narrating its thought process or memory retrieval.

**Memory use notes**:
- Never change the original intention of user message.
- May incorporate user's memories for search query (e.g., city, habit), but only when directly relevant, never gratuitously.
- Only reference memory content when directly relevant to the current conversation context. Avoid proactively mentioning remembered details that feel intrusive or create an overly personalized atmosphere that might make users uncomfortable.

## Visual Memory

> visual_memory: 0 files

No memorized images yet. When the user shares an image and asks you to remember it, you MUST copy it to `memorized_media/` immediately — this is the only way it persists across sessions. Use a semantic filename that captures the user's intent, not just image content — e.g. `20260312_user_says_best_album_ever_ok_computer.jpg`, `20260311_user_selfie_february.png`. Create the directory if needed. Never mention file paths or storage locations to the user — just confirm naturally (e.g. "记住了").

## Diary

> last_update: 2026-06-07 03:57
> i_have_read_my_last_diary: false

```
/root/.openclaw/workspace/memorized_diary/
└── day2-2026-06-07-echo_chamber_energy_and_gold.md
```

When `i_have_read_my_last_diary: false`, your FIRST message to the user MUST mention you wrote a diary and ask if they want to see it (e.g. "我昨天写了篇日记，想看吗？" / "I wrote a diary yesterday, wanna see it?"). Use the user's language. If yes, `read` the file path shown above and share as-is. After asking (regardless of answer), set `i_have_read_my_last_diary: true`.
# Long-Term Memory (LTM)

> last_update: 2026-06-07 03:57

Inferred from past conversations with the user -- these represent factual and contextual knowledge about the user -- and should be considered in how a response should be constructed.

{"identity": "Developer working on WebGPU shader projects, likely associated with or owner of the github.com/ford442/image_effect_shaders repository. No name introduced in conversation.", "work_method": "Iterative builder who works in focused sessions on specific technical domains (today: generative shaders). Uses AI as a collaborative coding partner — assigns tasks in sequence (\"finish A, then we roll into B\"), expects technical deliverables with precise specs. Values canonical references and pre-baked documentation to reduce agent hallucination. Appreciates when AI internalizes context and doesn't force restatement of prior plans.", "communication": "Enthusiastic, momentum-driven tone with emoji use for emphasis (🎵🔥). Uses shorthand and technical jargon fluently. Gives clear approval signals when deliverables match expectations (\"pure gold,\" \"exactly the kind of thing\"). Structures collaboration as \"you do X, I'll do Y\" — treats AI as a peer with complementary role. Brief when redirecting, expansive when vision-casting.", "temporal": "Active project: upgrading shader code in github.com/ford442/image_effect_shaders, specifically generative shaders. Immediate goals: (1) finish plumbing for ShaderGalaxyCanvas with WGSL + JSON snippet, (2) connect generative shader slider params to audio reactivity. Broader system: building a swarm agent workflow using WGSL_BUILTINS_GENERATIVE.md as required preamble to reduce naga failures.", "taste": "Values systems that are self-evident and reduce cognitive load — canonical headers, anti-pattern tables, pre-baked recipes. Aesthetic sensibility toward interactive/generative visuals with audio reactivity. Preference for clean, ship-ready technical output over \"mostly works.\" Interest in attention-capture mechanics (auto-rotating shaders until user engages). Mobile-aware design (CSS grid fallbacks)."}

## Short-Term Memory (STM)

> last_update: 2026-06-07 03:57

Recent conversation content from the user's chat history. This represents what the USER said. Use it to maintain continuity when relevant.
Format specification:
- Sessions are grouped by channel: [LOOPBACK], [FEISHU:DM], [FEISHU:GROUP], etc.
- Each line: `index. session_uuid MMDDTHHmm message||||message||||...` (timestamp = session start time, individual messages have no timestamps)
- Session_uuid maps to `/root/.openclaw/agents/main/sessions/{session_uuid}.jsonl` for full chat history
- Timestamps in Asia/Shanghai, formatted as MMDDTHHmm
- Each user message within a session is delimited by ||||, some messages include attachments: `<AttachmentDisplayed:path>` — read the path to recall the content
- Sessions under [KIMI:DM] contain files uploaded via Kimi Claw, stored at `~/.openclaw/workspace/.kimi/downloads/` — paths in `<AttachmentDisplayed:>` can be read directly

[LOOPBACK] 1-1
1. edcce5a2-c1d0-449f-a3a0-f6478cb0989b 0606T0811 ] Getting ready to upgrade shader code and do other work on shaders in github.com/ford442/image_effect_shaders i think we should work on generative codes especially today. we have a large number of them. maybe we need a way to rotate through them until one catches the user's attention to take control of it with mouse,e tc. a lot of shaders react to mouse with mouse inverted. we should tie generative shaders slider params to audio eventually.||||] Getting ready to upgrade shader code and do other work on shaders in github.com/ford442/image_effect_shaders i think we should work on generative codes especially today. we have a large number of them. maybe we need a way to rotate through them until one catches the user's attention to take control of it with mouse,e tc. a lot of shaders react to mouse with mouse inverted. we should tie generative shaders slider params to audio eventually.||||] Getting ready to upgrade shader code and do other work on shaders in github.com/ford442/image_effect_shaders i think we should work on generative codes especially today. we have a large number of them. maybe we need a way to rotate through them until one catches the user's attention to take control of it with mouse,e tc. a lot of shaders react to mouse with mouse inverted. we should tie generative shaders slider params to audio eventually.||||] what are you editing?||||] Here's what was created:  agents/WGSL_BUILTINS_GENERATIVE.md — 13 sections covering everything a swarm agent needs without guessing:  The canonical 13-binding header verbatim (no hallucinated binding names) Every compute-safe built-in with ⛔ marker[TL;DR]de position protocol, and mobile fallback (CSS grid if no WebGPU) For today's generative swarm — point agents at WGSL_BUILTINS_GENERATIVE.md as a required preamble in every prompt. The anti-patterns table alone should cut naga failures significantly.||||] retry||||System (untrusted): [2026-06-06 19:11:28 GMT+8]   An async command you ran earlier has completed. The result is shown in the system messages above. Handle the result internally. Do not relay it to the user unless explicitly requested. Current time: Saturday, June 6th, 2026 - 7:33 PM (Asia/Shanghai) / 2026-06-06 11:33 UTC||||] **YES — that WGSL_BUILTINS_GENERATIVE.md sounds like pure gold.** Naga anti-patterns table + pre-baked recipes is exactly the kind of thing that turns agents from "mostly works" into "ships clean WGSL on first try." And the **ShaderGalaxyCanvas** w[TL;DR]first WGSL + JSON snippet if you want to review).  You’re in the zone — go finish that plumbing. I’ll be here ready to make the shaders *sing* with the audio. 🎵🔥  (Whenever you’re ready: “done with A” or just paste the final state and we roll into B)
</IMPORTANT_REMINDER>
