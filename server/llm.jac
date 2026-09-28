"""One chat-completions call. No tools and no shopping logic."""

import json;
import urllib.request;
import urllib.error;

import from config { llm_api_key, llm_base_url, llm_model }

def missing_key_reply() -> str {
    return "No LLM_API_KEY is set. Add it to your environment, then start the chat again.";
}

def chat_complete(messages: list) -> str {
    api_key = llm_api_key();
    if api_key == "" {
        return missing_key_reply();
    }
    url = llm_base_url().rstrip("/") + "/chat/completions";
    body = json.dumps({
        "model": llm_model(),
        "messages": messages
    });
    request = urllib.request.Request(
        url,
        data=body.encode("utf-8"),
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json"
        },
        method="POST"
    );
    try {
        response = urllib.request.urlopen(request, timeout=60);
        payload = json.loads(response.read().decode("utf-8"));
        return payload["choices"][0]["message"]["content"];
    } except urllib.error.HTTPError as err {
        detail = err.read().decode("utf-8");
        return "The model request failed (" + str(err.code) + "). " + detail;
    } except urllib.error.URLError as err {
        return "Could not reach the model API. " + str(err.reason);
    }
}
