"""Named authenticated shopping operations, scoped to the requesting root's profile."""
import from server.accounts { account_profile }

import from server.shopping { shopping_operation }
import from app_settings { stamp }
import from server.chat { send_message }

walker update_profile {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "update_profile", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker update_interest {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "save_interest", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker refresh_offers {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "refresh", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker build_candidates {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "plan", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker plan_shopping {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "plan", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker plan_action {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "plan_action", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker feedback {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "feedback", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker discover_products {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "discover", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker check_reminders {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "view", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker sync {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(account_profile(here), "sync", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker chat {
    has text: str = "", history: list = [];
    can run with Root entry {
        try { report send_message(account_profile(here), self.text); }
        except ValueError as err { report {"error": str(err)}; }
    }
}
