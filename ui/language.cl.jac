"""English application chrome and constraint messages, independent of browser locale."""

def validation_message(field: any) -> str {
    state = field.validity;
    if state.badInput { return "Please enter a valid number."; }
    if state.valueMissing { return "Please fill out this field."; }
    if state.typeMismatch { return "Please enter a valid " + ("email address." if field.type == "email" else "value."); }
    if state.rangeUnderflow { return "Please enter a value greater than or equal to " + field.min + "."; }
    if state.rangeOverflow { return "Please enter a value less than or equal to " + field.max + "."; }
    if state.stepMismatch {
        if field.type in ["number", "range"] { return "Please enter a value in increments of " + (field.step or "1") + "."; }
        return "Please choose a valid date or time.";
    }
    if state.tooShort { return "Please use at least " + str(field.minLength) + " characters."; }
    if state.tooLong { return "Please use no more than " + str(field.maxLength) + " characters."; }
    if state.patternMismatch { return "Please match the requested format."; }
    return "Please check this value.";
}

def:pub install_english_ui() -> any {
    document.documentElement.lang = "en";
    document.documentElement.setAttribute("translate", "no");
    document.documentElement.classList.add("notranslate");
    # Capture also covers controls mounted later, including dialogs and dynamic list rows.
    invalid = lambda e: any {
        field = e.target;
        if field.setCustomValidity and field.validity {
            field.setCustomValidity(validation_message(field));
            field.dataset.cartcompassValidation = "true";
        }
    };
    clear = lambda e: any {
        field = e.target;
        if field.setCustomValidity and field.dataset.cartcompassValidation == "true" {
            field.setCustomValidity("");
            field.removeAttribute("data-cartcompass-validation");
        }
    };
    document.addEventListener("invalid", invalid, True);
    document.addEventListener("input", clear, True);
    document.addEventListener("change", clear, True);
    return lambda {
        document.removeEventListener("invalid", invalid, True);
        document.removeEventListener("input", clear, True);
        document.removeEventListener("change", clear, True);
    };
}
