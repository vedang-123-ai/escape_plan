# S11.45 — The assistant keeps one conversation per home and a bounded history

- **Who:** Claude session for Anish
- **Date(s):** 2026-10-04
- **Status when I stopped:** done and merged. AUD-033 and the Assistant item of AUD-049 are fixed.

## What happened
- `ConversationStore` now keeps one file per home, `Documents/Assistant/<home_id>.json`. Every path goes
  through `HomeID.validate` (S11.41). `load(forHomeID:)` throws:
  - when a file does not decode, it is renamed aside and the error is `UnreadableConversation`;
  - when a file cannot be read, the error is rethrown and the file stays where it is.
  `save` and `clear` throw. `migrateLegacyConversation()` moves the old `conversation.json` to its home, or renames
  it aside. `deleteConversation` removes the thread and its kept-aside copies.
- `ChatHistory.trimmed` in `APIClient+Chat.swift` caps what is sent to the server's limits from
  `backend/app/limits.py`. A test reads that Python file and compares the numbers.
- `AssistantScreen` changes:
  - loads per home, and runs the migration before each load (one existence check);
  - sends only the trimmed history;
  - shows save, clear, load and migration problems in the existing "history can't be saved" line;
  - blocks saving for a home whose file could not be read;
  - shows "Older messages stay here but aren't sent with new questions." when turns are left out;
  - disables New chat while a reply is on its way.
- `HomeLibrary.delete` deletes the home's thread, and still does when the sync tombstone fails.
- Mutation checks. Each run broke the code on purpose and went red, then I restored the files by copying from the
  scratchpad backups:
  - **mutA**, 7 red: corrupt file silently ignored; unmatchable old file deleted; existing thread overwritten by
    the migration; kept-aside copies not deleted; id validation removed; save `try?`; HomeLibrary hook removed.
    Corrupt-file, mismatch, hostile-id, overwrite, unmatchable, save-failure and library-delete tests went red.
  - **mutB**, 12 red: `maxMessages` 41; grapheme counting; skipping an overlong turn instead of stopping;
    leading assistant turn kept; one fixed file name for every home; kept-aside copies not deleted. The
    caps-match-server, count, total, hole, unicode, isolation, new-chat, migration and delete tests went red.
  - **mutC**, 2 red: the final message is not always kept. The final-question and unicode tests went red.
  - **mutD**, 4 red: read failures swallowed in `load` and in the migration; the `conversation` guard removed;
    tombstone-first ordering. All four new reviewer-follow-up tests went red.
- Reviewers:
  - swift-scenekit-reviewer and ecc:silent-failure-hunter found the same HIGH issue: a file that cannot be read
    could be saved over. They also found that the tombstone failure skipped the thread delete. Both are fixed and
    tested.
  - Also fixed: the migration's "kept aside" was not shown; a read error diverted an old file; the late-reply race
    on New chat; the `conversation` id collision.
  - Left in BLOCKERS: test isolation for `HomeLibrary.conversations`; kept-aside files are never cleaned.

## Decisions / surprises
- The server counts characters with Python's `len` (Unicode scalars). Swift's `String.count` counts graphemes, so
  a flag emoji counts as 1 in Swift and 2 on the server. Trimming counts scalars.
- The Anthropic chat reply is capped at 1024 tokens, so an assistant turn over 8,000 characters is not realistic.
  The trimmer still handles one by ending the run there.
- No new Swift files. No backend, corpus, schema or user-facing safety text was touched.

## Questions for teammates
- None blocking. The device check (a long chat shows the quiet line; switching homes keeps both threads) is in
  BLOCKERS.

## Next steps
- None owned. See the S11.45 section of BLOCKERS for the small open items.
