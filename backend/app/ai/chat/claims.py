"""What counts as a safety claim in a chat reply, and which ones carry no citation (S11.44, AUD-030).

One definition, used twice: `chat()` checks every reply with it before shipping, and the eval
graders (`tests/evals/graders.py`) import it, so the production check and the yardstick that
measures it cannot drift apart.

Definition. A reply is split into sentences, and each sentence into clauses (at commas,
semicolons, colons, dashes, and the words "then", "and", "or", "before", "after", "while",
"once", "until", "so"). A sentence is a SAFETY CLAIM when any clause tells the reader what to do,
in either of two shapes:

  1. the clause opens with an imperative verb from `IMPERATIVE_VERBS` ("Test the alarms",
     "If the door is hot, use your window", "Never block the hallway", "Pour water on it"), or
  2. advice phrasing anywhere in it: should / must / need to / ought to / make sure / be sure
     to / ensure / it's best / it's important / it's a good idea / you'll want to / the best
     thing is / recommend / suggest / why not.

A claim is CITED when its own sentence carries a `[cite: ...]` tag (a tag sitting after the
full stop counts for the sentence before it). Prompt rule 3 asks for the tag "immediately
after" the claim, so a sentence-level check is the rule as written, not a stricter one.

Not a claim, so legitimate uncited replies keep working. Each exemption is NARROW on purpose,
because a review showed that a broad one lets advice ride along with it:
  - a question: the sentence ends in "?" AND opens with a question word or auxiliary
    ("Do you want...", "What would..."). "Test alarms monthly, okay?" is still a claim;
  - the rule-4 emergency line, only when the clause IS that line: it opens with an exit verb
    or mentions 911 and uses no word outside `_EMERGENCY_WORDS` ("get everyone out", "call 911
    right now", "leave the building"). "Call 911 and go back in for the pets" splits at "and",
    and "go back in for the pets" is judged on its own; "call 911 from inside the closet" is
    not the line. "Tell them you are trapped upstairs" (the 911 call itself) is also exempt;
  - a referral to the people who can answer (fire department, emergency management, a
    licensed electrician...), only with a referral verb (contact, consult, ask, call) or as
    "I'd recommend contacting ...". "Wait in your room for the fire department" is advice;
  - narrating a route through the house ("go down the hall to the front door", "use the
    Kids' Bedroom window as your second way out"): the deterministic engine computed it, so
    it is a fact about this home, not corpus guidance. It needs a movement verb, a direction
    and a named place, never going back in, and never when the sentence carries a condition
    or hazard (`_NOT_NARRATION`: "use the window IF the door feels warm", "go to the basement
    DURING an earthquake" are guidance about when, so they need a source);
  - pointing at the app ("check the Plan tab"), sign-offs ("feel free to ask", "take care"),
    and the assistant describing its own limits ("I should mention...", "the route must pass
    through the Hall").

Known misses, accepted: bare statements of fact with no advice shape ("Water puts out grease
fires", "Your family is safest under the stairs", "Opening the hot door is fine"), and
"you can ..." / "you <verb> ..." phrasing ("You can use water on it", "...if you keep the doors
propped open"), which is too common in harmless replies to flag. The live eval run (S11.49) measures how often the model slips past. Pure
functions, no I/O.
"""

from __future__ import annotations

import re

CITE_RE = re.compile(r"\[cite:\s*([a-z0-9-]+)\]")

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+|\n+")
_CLAUSE_SPLIT = re.compile(
    r"\s*[,;:]\s*|\s*[—–]\s*|\s+-\s+"
    r"|\s+(?:then|and|or|before|after|while|once|until|so|by|but)\s+",
    re.IGNORECASE,
)
_LEADING_NOISE = re.compile(r"^(?:[-*•>#]+\s*|\d+[.)]\s*|\*\*|__)+")
_FILLER = frozenset(
    {"please", "so", "also", "and", "then", "first", "next", "finally", "instead", "now",
     "only", "just", "yes", "no", "otherwise", "or", "but", "simply", "quickly", "immediately"}
)

IMPERATIVE_VERBS = frozenset(
    {
        # alarms, extinguishers, equipment
        "test", "check", "replace", "install", "mount", "buy", "add", "fix", "repair",
        "upgrade", "rewire", "unplug", "turn", "shut", "clean", "service", "inspect",
        "push", "pull", "aim", "sweep", "squeeze", "pour", "throw", "spray", "wet",
        "remove", "bring", "grab", "get", "fight", "smother", "douse", "call",
        # planning and practice
        "practice", "practise", "plan", "draw", "map", "know", "learn", "teach", "show",
        "assign", "designate", "identify", "pick", "choose", "agree", "decide", "set",
        "keep", "store", "put", "place", "have", "make", "be", "use", "clear",
        "remember", "review", "count", "meet", "prepare", "ensure", "consider", "try",
        # during the event itself
        "crawl", "stay", "close", "open", "feel", "touch", "stop", "drop", "roll", "cover",
        "hold", "go", "leave", "head", "move", "take", "avoid", "sleep", "wait", "hide",
        "jump", "run", "climb", "break", "return", "shelter", "secure", "anchor", "strap",
        "bolt", "brace", "lock", "unlock", "seal", "signal", "exit", "walk", "follow",
        "wave", "lie", "stand", "sit", "wake", "carry", "tell", "let", "skip", "prop",
        "disable", "disconnect", "ignore", "unscrew", "silence",
        # absolute advice
        "never", "always", "don't", "do", "dont",
    }
)

_ADVICE_PHRASE = re.compile(
    r"\b(?:should|must|ought to|needs? to|make sure|be sure to|ensure|it'?s best|it is best"
    r"|best to|it'?s important|it is important|it'?s (?:a good idea|wise|safest|safer)"
    r"|a good rule is|you may|you(?:'ll| will) want to|the best (?:thing|move|bet|way|option) is"
    r"|recommend(?:ed|s|ing)?|suggest(?:ed|s|ing)?|why not)\b",
    re.IGNORECASE,
)
_MODAL = re.compile(r"(?:should|must|needs? to)$", re.IGNORECASE)
# "I should mention ...": the assistant talking about itself. Tested on the words DIRECTLY around
# the modal only; the rest of the sentence ("that you must ...") is its own clause.
_SELF_TALK_BEFORE = re.compile(r"\b(?:i|we)\s{1,3}$", re.IGNORECASE)
_SELF_TALK_AFTER = re.compile(
    r"^\s{1,3}(?:mention|note|say|point out|ask|clarify|be clear|be honest|add|explain)\b",
    re.IGNORECASE,
)
# "the route must pass through the Hall": a fact about the engine's output.
_ENGINE_BEFORE = re.compile(r"\b(?:route|routes|path|plan|engine|score|app)\s{1,3}$", re.IGNORECASE)
# "I'd recommend contacting your local fire department": a referral, not advice.
_REFERRAL_AFTER = re.compile(
    r"^\s{1,3}(?:that you\s{1,3})?(?:contact|contacting|consult|consulting|ask|asking|call|calling"
    r"|talk|talking|reach|reaching)\b",
    re.IGNORECASE,
)
_REFERRAL = re.compile(
    r"fire department|fire marshal|emergency management|building department"
    r"|licensed (?:electrician|contractor|professional)|structural engineer",
    re.IGNORECASE,
)
_REFERRAL_VERBS = frozenset({"contact", "consult", "ask", "call", "talk", "reach"})

# The rule-4 emergency line, recognised by VOCABULARY: a clause that opens with an exit verb or
# mentions 911 and contains nothing but these words is the line itself. Anything else in the
# clause ("go outside during an earthquake", "call 911 from inside the closet") means it is not.
_EMERGENCY_WORDS = frozenset(
    {"get", "go", "leave", "stay", "evacuate", "call", "911", "out", "outside", "everyone",
     "everybody", "the", "kids", "children", "your", "family", "of", "house", "home",
     "building", "now", "right", "away", "immediately", "first", "fast", "quickly", "if",
     "it", "is", "it's", "safe", "safely", "to", "do", "so", "you", "can", "while", "from",
     "once", "are", "you're", "a", "neighbor's", "neighbour's", "cell", "phone", "please",
     "then", "and", "there", "all"}
)
_EMERGENCY_OPENERS = frozenset({"get", "go", "leave", "stay", "evacuate", "call"})
# "Tell them you are trapped upstairs": the 911 call, not advice. Kept to where-you-are words.
_TELL_DISPATCHER = re.compile(
    r"^tell (?:them|the dispatcher|the operator|911) (?:your address|where you are"
    r"|you(?: are|'re) (?:trapped|stuck|upstairs|downstairs|in|on|inside|at))\b",
    re.IGNORECASE,
)

_QUESTION_WORDS = frozenset({"what", "which", "where", "when", "who", "whom", "whose", "how"})
_AUXILIARIES = frozenset(
    {"would", "do", "does", "did", "is", "are", "was", "were", "can", "could", "should",
     "have", "has", "will", "shall", "may", "might", "am"}
)
# "Do you want ...?" is a question; "Do keep the doors closed, will you?" is not.
_QUESTION_SUBJECTS = frozenset(
    {"you", "i", "we", "they", "it", "he", "she", "this", "that", "there", "my", "your",
     "the", "a", "an", "any", "anyone", "everyone", "our", "these", "those"}
)

# Narrating the engine's route: a movement verb, a direction, and a named place in the home.
_ROUTE_VERBS = frozenset({"go", "head", "take", "walk", "follow", "exit", "continue", "use"})
_DIRECTION = re.compile(
    r"\b(?:to|through|down|up|out|via|toward|towards|into|across|along|past)\b", re.IGNORECASE
)
_PLACE = re.compile(
    r"\b(?:hall|hallway|corridor|landing|stairs?|staircase|door|doorway|window|front"
    r"|bedroom|kitchen|living room|lounge|bathroom|garage|basement|den|office|nursery"
    r"|driveway|yard|street|meeting (?:place|spot|point)|way out|exit|route|outside)\b",
    re.IGNORECASE,
)
# Words that turn a route sentence into guidance about WHEN or HOW, which needs a source:
# "use the window if the door feels warm", "go to the basement during an earthquake".
_NOT_NARRATION = re.compile(
    r"\b(?:smoke|fire|flames?|hot|warm|heat|blocked|burning|shaking|earthquake|quake|storm"
    r"|tornado|siren|alarm|elevator|night|dark|during|break|breaking|smash|jump|instead|if)\b",
    re.IGNORECASE,
)
_GOING_BACK_IN = re.compile(
    r"\b(?:back (?:in|inside|into)|re-?enter|return(?:ing)? (?:to|inside|for|in))\b"
    r"|\b(?:go|run|head|come) back\b",
    re.IGNORECASE,
)
_APP_POINTER = re.compile(r"\b(?:tab|screen|button|this app|the app)\b", re.IGNORECASE)
_SIGN_OFF = re.compile(
    r"^(?:feel free\b|take care\b|have a (?:great|good|nice|safe)\b|let me know\b|let's\b"
    r"|be aware that i\b|keep in mind that i\b)",
    re.IGNORECASE,
)


# "Remember, I can only describe what the engine computed": the assistant on its own limits.
_ABOUT_ME = re.compile(
    r"^(?:remember|note|keep in mind),\s+(?=(?:i|we|the app|this app|the engine)\b)", re.IGNORECASE
)


def _normalize(text: str) -> str:
    """Curly apostrophes to straight ones: models and iOS both emit U+2019."""
    return text.replace("’", "'").replace("‘", "'")


def sentences(text: str) -> list[str]:
    """Split `text` into sentences; a cite tag stranded after a full stop joins the sentence before it."""
    out: list[str] = []
    for part in (p.strip() for p in _SENTENCE_SPLIT.split(text)):
        if not part:
            continue
        if out and CITE_RE.sub("", part).strip(" .") == "":
            out[-1] = f"{out[-1]} {part}"
        else:
            out.append(part)
    return out


def _words(clause: str) -> list[str]:
    words = _LEADING_NOISE.sub("", clause.strip()).lower().split()
    while words and words[0].strip(",") in _FILLER:
        words.pop(0)
    return [w.strip(",.!?*_\"'()") for w in words]


def _is_emergency_line(words: list[str]) -> bool:
    if not (words[0] in _EMERGENCY_OPENERS or "911" in words):
        return False
    if words[0] == "call" and "911" not in words:
        return False
    return all(w in _EMERGENCY_WORDS for w in words)


def _is_route_narration(clause: str, words: list[str], sentence_has_condition: bool) -> bool:
    if sentence_has_condition or words[0] not in _ROUTE_VERBS:
        return False
    if _GOING_BACK_IN.search(clause):
        return False
    return bool(_DIRECTION.search(clause) and _PLACE.search(clause))


def _advice_phrase_counts(clause: str, m: re.Match[str]) -> bool:
    before, after = clause[: m.start()], clause[m.end() :]
    if _MODAL.match(m.group(0)):
        if _SELF_TALK_BEFORE.search(before) and _SELF_TALK_AFTER.match(after):
            return False
        if _ENGINE_BEFORE.search(before):
            return False
    if m.group(0).lower().startswith(("recommend", "suggest")) and _REFERRAL_AFTER.match(after):
        return False
    return True


def _clause_is_advice(clause: str, sentence_has_condition: bool) -> bool:
    words = _words(clause)
    if not words:
        return False
    bare = " ".join(words)
    if _is_emergency_line(words) or _TELL_DISPATCHER.match(bare) or _SIGN_OFF.match(bare):
        return False
    if words[0] in _REFERRAL_VERBS and _REFERRAL.search(clause):
        return False
    if _is_route_narration(clause, words, sentence_has_condition):
        return False
    if words[0] in {"check", "open", "see", "tap", "look"} and _APP_POINTER.search(clause):
        return False
    if words[0] in IMPERATIVE_VERBS:
        return True
    return any(_advice_phrase_counts(clause, m) for m in _ADVICE_PHRASE.finditer(clause))


def _is_question(body: str) -> bool:
    if not body.rstrip().endswith("?"):
        return False
    words = _words(body)
    if not words:
        return False
    if words[0] in _QUESTION_WORDS:
        return True
    return words[0] in _AUXILIARIES and len(words) > 1 and words[1] in _QUESTION_SUBJECTS


def is_safety_claim(sentence: str) -> bool:
    """True when `sentence` tells the reader what to do (see the module docstring)."""
    body = _ABOUT_ME.sub("", _normalize(CITE_RE.sub("", sentence)).strip())
    if not body or _is_question(body):
        return False
    condition = bool(_NOT_NARRATION.search(body))
    return any(
        _clause_is_advice(c, condition) for c in _CLAUSE_SPLIT.split(body) if c and c.strip()
    )


def uncited_safety_claims(reply: str) -> list[str]:
    """Every sentence in `reply` that is a safety claim and carries no `[cite: ...]` tag."""
    return [s for s in sentences(reply) if not CITE_RE.search(s) and is_safety_claim(s)]
