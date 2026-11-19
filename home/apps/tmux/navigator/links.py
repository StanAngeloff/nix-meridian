"""Links in the navigator's text: the patterns Claude Code links in its footer (home/apps/claude-code/footer-links.nix),
so an issue named in a window's title or a pane's task opens on Ctrl+click, as it does in Claude Code.

The navigator writes each link as OSC 8, which tmux keeps with the text and passes on to the terminal (the hyperlinks
terminal feature in tmux.conf).
"""

import json
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

# Written beside the navigator by package.nix; run from the source tree, there is none and nothing links.
RULES_PATH = Path(__file__).with_name("links.json")
# A named group as JavaScript writes it, (?<name>, which Python spells (?P<name>; (?<= and (?<! are lookbehinds in both.
JAVASCRIPT_GROUP = re.compile(r"\(\?<(?![=!])")
# A {name} in a URL, filled with the group of that name.
PLACEHOLDER = re.compile(r"\{(\w+)\}")


@dataclass
class Rule:
    pattern: re.Pattern
    url: str


def compile_rules(entries: list[dict]) -> list[Rule]:
    """Claude Code's footer links as rules, ASCII-only as JavaScript reads \\b and \\d without its u flag. A pattern
    Python cannot read is left out."""
    rules = []
    for entry in entries:
        if entry.get("type") != "regex":
            continue
        try:
            pattern = re.compile(
                JAVASCRIPT_GROUP.sub("(?P<", entry["pattern"]), re.ASCII
            )
        except re.error:
            continue
        rules.append(Rule(pattern, entry["url"]))
    return rules


def load() -> list[Rule]:
    try:
        return compile_rules(json.loads(RULES_PATH.read_text()))
    except FileNotFoundError:
        return []


def urls(text: str, rules: list[Rule]) -> list[str]:
    """The link of each character of text, empty where it has none; where two rules match, the earlier one wins."""
    result = [""] * len(text)
    for rule in rules:
        for match in rule.pattern.finditer(text):
            groups = match.groupdict()
            # Quoted, so text from a title cannot end the escape sequence the link travels in.
            url = PLACEHOLDER.sub(
                lambda m: quote(groups.get(m[1]) or "", safe=""), rule.url
            )
            for i in range(match.start(), match.end()):
                result[i] = result[i] or url
    return result
