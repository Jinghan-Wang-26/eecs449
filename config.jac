"""Runtime settings. The shopping harness does not read these yet."""

import os;
import pathlib;

glob LLM_BASE_URL: str = "https://api.openai.com/v1";
glob LLM_MODEL: str = "gpt-4o-mini";
glob SYSTEM_PROMPT: str = "You are CartCompass, a shopping assistant for everyday errands in the U.S. The planning harness is not connected yet, so you cannot look up prices, stock, routes, or delivery fees. Talk with the user about what they need, where they live, how they travel, and what constraints matter. Do not invent prices, availability, or routes. If they ask for a concrete shopping plan, say that part is still being built.";

def load_env_file() -> None {
    if os.getenv("CARTCOMPASS_ENV_LOADED") == "1" {
        return;
    }
    os.environ["CARTCOMPASS_ENV_LOADED"] = "1";
    path = pathlib.Path(".env");
    if not path.is_file() {
        return;
    }
    for line in path.read_text().splitlines() {
        stripped = line.strip();
        if stripped == "" or stripped.startswith("#") {
            continue;
        }
        if stripped.startswith("export ") {
            stripped = stripped[7:].strip();
        }
        eq = stripped.find("=");
        if eq <= 0 {
            continue;
        }
        name = stripped[:eq].strip();
        value = stripped[eq + 1:].strip();
        if len(value) >= 2 and value[0] == value[-1] and (value[0] == "\"" or value[0] == "'") {
            value = value[1:-1];
        }
        if os.getenv(name) is None {
            os.environ[name] = value;
        }
    }
}

def llm_api_key() -> str {
    load_env_file();
    key = os.getenv("LLM_API_KEY");
    if key is None {
        return "";
    }
    return key;
}

def llm_base_url() -> str {
    load_env_file();
    value = os.getenv("LLM_BASE_URL");
    if value is None or value == "" {
        return LLM_BASE_URL;
    }
    return value;
}

def llm_model() -> str {
    load_env_file();
    value = os.getenv("LLM_MODEL");
    if value is None or value == "" {
        return LLM_MODEL;
    }
    return value;
}
