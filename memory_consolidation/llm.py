# memory_consolidation/llm.py
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

KIMI_CREDENTIALS_PATH = Path.home() / ".kimi" / "credentials" / "kimi-code.json"
KIMI_OAUTH_CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098"
KIMI_OAUTH_HOST = "https://auth.kimi.com"
KIMI_API_BASE = "https://api.kimi.com/coding/v1"
KIMI_OAUTH_HEADERS = {"User-Agent": "KimiCLI/0.79", "X-Msh-Platform": "kimi_cli"}


def _load_oauth_token() -> str | None:
    """Load OAuth access_token from kimi-cli credentials. Auto-refresh if expired."""
    if not KIMI_CREDENTIALS_PATH.exists():
        return None
    try:
        creds = json.loads(KIMI_CREDENTIALS_PATH.read_text())
    except Exception:
        return None

    if time.time() > creds.get("expires_at", 0):
        refresh = creds.get("refresh_token", "")
        if not refresh:
            return None
        try:
            data = urllib.parse.urlencode({
                "client_id": KIMI_OAUTH_CLIENT_ID,
                "grant_type": "refresh_token",
                "refresh_token": refresh,
            }).encode()
            req = urllib.request.Request(
                f"{KIMI_OAUTH_HOST}/api/oauth/token",
                data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded", **KIMI_OAUTH_HEADERS},
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                new = json.loads(resp.read())
            creds["access_token"] = new["access_token"]
            creds["refresh_token"] = new["refresh_token"]
            creds["expires_at"] = time.time() + new.get("expires_in", 900)
            KIMI_CREDENTIALS_PATH.write_text(json.dumps(creds, ensure_ascii=False))
            print("  OAuth token refreshed.")
        except Exception as e:
            print(f"  OAuth refresh failed: {e}")
            return None

    return creds.get("access_token")


def _resolve_from_kimi_oauth() -> dict | None:
    """Resolve LLM config from kimi-cli OAuth credentials (production machines)."""
    token = _load_oauth_token()
    if not token:
        return None

    model_id = "kimi-for-coding"
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError:
            tomllib = None
    if tomllib:
        config_path = Path.home() / ".kimi" / "config.toml"
        if config_path.exists():
            try:
                with open(config_path, "rb") as f:
                    cfg = tomllib.load(f)
                default_model = cfg.get("default_model", "")
                model_cfg = cfg.get("models", {}).get(default_model, {})
                if model_cfg.get("model"):
                    model_id = model_cfg["model"]
            except Exception:
                pass

    return {
        "base_url": KIMI_API_BASE,
        "api": "openai-completions",
        "api_key": token,
        "model": model_id,
        "headers": KIMI_OAUTH_HEADERS,
        "_source": "kimi-cli (OAuth)",
    }


def resolve_llm_config(oc_config: dict, env_api_key: str = "") -> dict:
    """Resolve LLM endpoint. Priority:

    1. CLI arg --api-key (env_api_key)
    2. kimi-cli OAuth credentials (~/.kimi/credentials/kimi-code.json)
    3. openclaw.json provider (may not work for external HTTP calls)
    """
    if env_api_key:
        raw = oc_config.get("raw", {})
        providers = raw.get("models", {}).get("providers", {})
        primary = raw.get("agents", {}).get("defaults", {}).get("model", {}).get("primary", "")
        provider_id = primary.split("/")[0] if "/" in primary else ""
        provider = providers.get(provider_id, {})
        return {
            "base_url": provider.get("baseUrl", KIMI_API_BASE).rstrip("/"),
            "api": provider.get("api", "openai-completions"),
            "api_key": env_api_key,
            "model": primary.split("/")[1] if "/" in primary else "kimi-k2.5",
            "headers": provider.get("headers", {}),
        }

    oauth_cfg = _resolve_from_kimi_oauth()
    if oauth_cfg:
        return oauth_cfg

    raw = oc_config.get("raw", {})
    providers = raw.get("models", {}).get("providers", {})
    primary = raw.get("agents", {}).get("defaults", {}).get("model", {}).get("primary", "")
    provider_id = primary.split("/")[0] if "/" in primary else ""
    provider = providers.get(provider_id, {})
    base_url = provider.get("baseUrl", "").rstrip("/")
    api = provider.get("api", "openai-completions")
    api_key = provider.get("apiKey", "")
    model_id = primary.split("/")[1] if "/" in primary else "kimi-k2.5"
    headers = provider.get("headers", {})

    for m in provider.get("models", []):
        if m.get("id") == model_id:
            headers = {**headers, **m.get("headers", {})}
            break

    return {
        "base_url": base_url,
        "api": api,
        "api_key": api_key,
        "model": model_id,
        "headers": headers,
    }


def call_llm(config: dict, messages: list[dict], json_mode: bool = True, max_retries: int = 3) -> str:
    """Call LLM via urllib. Supports openai and anthropic formats. Retries on 429."""
    for attempt in range(max_retries):
        try:
            return _call_llm_once(config, messages, json_mode)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < max_retries - 1:
                wait = (attempt + 1) * 10
                print(f"  429 rate limited, retrying in {wait}s (attempt {attempt + 1}/{max_retries})...")
                time.sleep(wait)
                continue
            raise
    return ""


def _call_llm_once(config: dict, messages: list[dict], json_mode: bool = True) -> str:
    """Single LLM call attempt."""
    api = config["api"]

    if api == "anthropic-messages":
        system_text = ""
        user_messages = []
        for m in messages:
            if m["role"] == "system":
                system_text = m["content"]
            else:
                user_messages.append(m)

        payload = json.dumps({
            "model": config["model"],
            "system": system_text,
            "messages": user_messages,
            "max_tokens": 8192,
        }).encode()

        headers = {
            "x-api-key": config["api_key"],
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01",
            **config.get("headers", {}),
        }
        url = f"{config['base_url']}/v1/messages"

        req = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())

        text = data["content"][0]["text"].strip()
        if text.startswith("```"):
            text = re.sub(r"^```(?:json)?\s*\n?", "", text)
            text = re.sub(r"\n?```\s*$", "", text)
        return text

    else:
        api_key = config["api_key"]
        payload_dict = {
            "model": config["model"],
            "messages": messages,
            "temperature": 1,
            "thinking": {"type": "disabled"},
        }
        if json_mode:
            payload_dict["response_format"] = {"type": "json_object"}
        payload = json.dumps(payload_dict).encode()

        headers = {
            "Authorization": f"Bearer {api_key}" if not api_key.startswith("Bearer ") else api_key,
            "Content-Type": "application/json",
            **config.get("headers", {}),
        }
        url = f"{config['base_url']}/chat/completions"

        req = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())
        return data["choices"][0]["message"]["content"]
