"""CartCompass entry. The page mounts here; SendMessage is the chat API."""

import from server.chat { SendMessage, ChatHistory, StartShoppingPlan }
import from server.walkers { update_profile, update_interest, refresh_offers, build_candidates, plan_shopping, plan_action, feedback, discover_products, check_reminders, sync, chat }
import from server.shopping { ShoppingAction }

cl {
    import from .ui.chat { ChatApp }

    def:pub app -> JsxElement {
        return <ChatApp />;
    }
}
