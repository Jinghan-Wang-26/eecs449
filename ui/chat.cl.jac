"""Chat page. The planning panels will sit beside this later."""

sv import from ..server.chat { SendMessage }

def:pub ChatApp -> JsxElement {
    has messages: list[dict] = [],
        draft: str = "",
        pending: bool = False;

    async def send(e: FormEvent) -> None;

    # Keep the newest message in view.
    can with (messages, pending) entry {
        el: any = document.querySelector(".chat-log");
        if el {
            el.scrollTop = el.scrollHeight;
        }
    }

    return
        <div
            style={{
                "position": "fixed",
                "inset": "0",
                "background": "#f3efe6",
                "color": "#1c1917",
                "fontFamily": "Georgia, 'Iowan Old Style', serif"
            }}
        >
            <div
                style={{
                    "maxWidth": "760px",
                    "margin": "0 auto",
                    "height": "100%",
                    "boxSizing": "border-box",
                    "display": "flex",
                    "flexDirection": "column",
                    "padding": "28px 20px 20px"
                }}
            >
                <header style={{"marginBottom": "18px"}}>
                    <div style={{"fontSize": "13px", "letterSpacing": "0.14em", "textTransform": "uppercase", "color": "#78716c"}}>
                        CartCompass
                    </div>
                    <h1 style={{"margin": "6px 0 0", "fontSize": "32px", "fontWeight": "500"}}>
                        What do you need to buy?
                    </h1>
                    <p style={{"margin": "8px 0 0", "color": "#57534e", "fontFamily": "system-ui, sans-serif", "fontSize": "15px"}}>
                        Planning, prices, and routes are not connected yet.
                    </p>
                </header>
                <div
                    className="chat-log"
                    style={{
                        "flex": "1",
                        "minHeight": "0",
                        "overflowY": "auto",
                        "display": "flex",
                        "flexDirection": "column",
                        "gap": "12px",
                        "padding": "8px 0 16px"
                    }}
                >
                    {if len(messages) == 0 {
                        <p style={{"color": "#a8a29e", "fontFamily": "system-ui, sans-serif"}}>
                            Try: I need milk, eggs, and rice, and I take the bus.
                        </p>
                    }}
                    {[
                        <div
                            key={str(idx)}
                            style={{
                                "alignSelf": ("flex-end" if turn["role"] == "user" else "flex-start"),
                                "maxWidth": "80%",
                                "background": ("#3f6212" if turn["role"] == "user" else "#fffdf8"),
                                "color": ("#f7fee7" if turn["role"] == "user" else "#1c1917"),
                                "border": ("none" if turn["role"] == "user" else "1px solid #e7e0d4"),
                                "borderRadius": "16px",
                                "padding": "12px 14px",
                                "fontFamily": "system-ui, sans-serif",
                                "fontSize": "15px",
                                "lineHeight": "1.45",
                                "whiteSpace": "pre-wrap"
                            }}
                        >
                            <div style={{"fontSize": "11px", "letterSpacing": "0.08em", "textTransform": "uppercase", "opacity": "0.7", "marginBottom": "4px"}}>
                                {"You" if turn["role"] == "user" else "CartCompass"}
                            </div>
                            {turn["content"]}
                        </div>
                        for (idx, turn) in enumerate(messages)
                    ]}
                </div>
                <form
                    onSubmit={send}
                    style={{"display": "flex", "gap": "8px", "paddingTop": "8px"}}
                >
                    <input
                        type="text"
                        value={draft}
                        onChange={lambda e: ChangeEvent { draft = e.target.value; }}
                        placeholder="Tell me what you need"
                        style={{
                            "flex": "1",
                            "padding": "14px 16px",
                            "border": "1px solid #d6d3d1",
                            "borderRadius": "999px",
                            "background": "#fffdf8",
                            "fontSize": "16px",
                            "fontFamily": "system-ui, sans-serif"
                        }}
                    />
                    <button
                        type="submit"
                        disabled={pending}
                        style={{
                            "padding": "14px 22px",
                            "border": "none",
                            "borderRadius": "999px",
                            "background": "#3f6212",
                            "color": "#f7fee7",
                            "fontSize": "15px",
                            "fontFamily": "system-ui, sans-serif",
                            "cursor": "pointer"
                        }}
                    >
                        {"Sending" if pending else "Send"}
                    </button>
                </form>
            </div>
        </div>;
}
