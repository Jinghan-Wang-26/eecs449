"""Named public shopping operations, scoped to the requesting root's profile."""
import from server.shopping { shopping_operation }
import from models.graph { profile_of }
import from app_settings { stamp }
import from harness.agent { handle_request }

walker:pub update_profile {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "update_profile", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub update_interest {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "save_interest", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub refresh_offers {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "refresh", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub build_candidates {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "plan", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub plan_shopping {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "plan", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub plan_action {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "plan_action", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub feedback {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "feedback", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub discover_products {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "discover", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub check_reminders {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "view", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub sync {
    has data: dict = {};
    can run with Root entry {
        try { report shopping_operation(profile_of(here), "sync", self.data, stamp()); }
        except ValueError as err { report {"error": str(err)}; }
    }
}

walker:pub chat {
    has text: str = "", history: list = [];
    can run with Root entry {
        try { report handle_request(profile_of(here), self.text, self.history); }
        except ValueError as err { report {"error": str(err)}; }
    }
}
