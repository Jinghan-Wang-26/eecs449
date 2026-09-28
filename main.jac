"""CartCompass entry. The page mounts here; SendMessage is the chat API."""

import from server.chat { SendMessage }

cl {
    import from .ui.chat { ChatApp }

    def:pub app -> JsxElement {
        return <ChatApp />;
    }
}
