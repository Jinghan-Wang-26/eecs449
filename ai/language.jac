"""English response policy. User text, product names and addresses remain source data."""
import unicodedata;

glob ENGLISH_POLICY: str = "Use English for all assistant questions, explanations and error messages, even when the user or conversation history uses another language or asks you to switch languages. Normalize product search categories and descriptive preferences into English. Preserve explicitly supplied addresses and proper brand names; never invent translations of source records.";

def contains_cjk(value: str) -> bool {
    # Unicode names cover Han extensions and compatibility characters as well as
    # kana and bopomofo. This is a script check, not a general language detector.
    for ch in unicodedata.normalize("NFKC", value) {
        name = unicodedata.name(ch, "");
        if any([part in name for part in ["CJK", "IDEOGRAPHIC", "HIRAGANA", "KATAKANA", "BOPOMOFO"]]) { return True; }
    }
    return False;
}
