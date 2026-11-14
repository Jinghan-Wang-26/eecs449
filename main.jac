"""CartCompass entry. The page mounts here; SendMessage is the chat API."""

import from server.mobile_assets { serve_public_asset }
import from server.accounts { SessionInfo, LogoutSession }
import from server.chat { SendMessage, ChatHistory, StartShoppingPlan }
import from server.walkers { update_profile, update_interest, refresh_offers, build_candidates, plan_shopping, plan_action, feedback, discover_products, check_reminders, sync, chat }
import from server.shopping { ShoppingAction }
import from server.background { run_background_reminders }

cl {
    import from .ui.mobile { MobileApp }

    def:pub app -> JsxElement {
        return <MobileApp />;
    }
}
