# Implementation Decisions

Documented decisions that were not fully prescribed by `/spec`.

## Persistence: JSON files instead of SwiftData

**Choice:** `FileMatchStore` writes Codable `MatchState` JSON under Application Support.

**Why:** Simplifies unit testing with an in-memory store, keeps the event stream trivially serializable for WatchConnectivity and a future FastAPI API, and avoids SwiftData/WatchOS edge cases for V1.

## Watch ↔ iPhone sync: WatchConnectivity application context

**Choice:** Watch pushes active match + archive via `WCSession.updateApplicationContext` (and `sendMessage` when reachable). iPhone applies remote snapshots; Watch does not accept phone-authored score updates.

**Why:** Matches the architecture rule that the Watch is authoritative during live scoring. No CloudKit in V1.

## Deleting matches from history

**Choice:** Deletion lives on the iPhone only (swipe-to-delete, Edit mode, or a Delete button in match detail), and the iPhone is authoritative for it. Deleted IDs are kept as tombstones in `deleted-matches.json`; `MatchService` filters every archive read and every remote snapshot through them, and the phone pushes the full tombstone set in each sync payload. The Watch accepts only the deletion key from an inbound payload — it prunes its own archive and never lets a phone payload touch the active match.

**Why:** The Watch pushes its whole archive and `applyRemoteSnapshot` replaces the phone's copy wholesale, so a delete without tombstones would be silently resurrected on the next sync. Tombstones make deletion durable even if the Watch is offline or never updates; sending the whole set rather than a delta lets a disconnected Watch catch up on its next context update. History curation is a phone-sized task, so this narrow inversion of authority does not disturb the rule that the Watch owns live scoring.

## Match notes

**Choice:** Free text notes are attached to a match on the iPhone (a Notes field in match detail, with a one-line preview in the history row). They live in their own phone-local `match-notes.json` keyed by match id, not as a field on `MatchState`, and are never sent to the Watch. The detail view saves its draft when the field loses focus, when the app leaves the foreground, and when the view goes away; deleting a match drops its note, and a tombstoned id refuses new notes so the dismissal save cannot resurrect one.

**Why:** The Watch pushes its whole archive and `applyRemoteSnapshot` replaces the phone's copy wholesale, so a note stored inside `MatchState` would be wiped on the next sync. Keeping notes in a side file — the same shape as the deletion tombstones — makes them immune to that without inverting any authority, and the Watch has no screen for them anyway. Saving on focus loss rather than per keystroke avoids rewriting the file while typing without risking the draft.

## Undo model

**Choice:** Undo removes the last `pointWon` event and replays the stream. After a point on the score screen, a 5-second clockwise outline animates on that side’s button; tapping the same button again cancels the point. Actions screen allows undo anytime while in progress.

**Why:** Keeps undo fast on the tiny Watch score surface without a separate Undo control, while Actions still covers recovering older mistakes. Replay keeps behaviour identical to event sourcing.

## Golden point house rule

**Choice:** First deuce → advantage → if advantage is broken, golden point activates; next point wins. Winning from advantage before that second deuce still wins the game normally.

**Why:** Exactly as specified in `spec/product.md` §14.

## Finish Match vs End Early

**Choice:** Finish with a natural match winner marks `completed`. Finish without a winner behaves like end-early for score retention. Explicit End Early always marks `endedEarly`. Discard is not archived.

**Why:** Product distinguishes completed, ended early, and discarded terminal states.

## Project generation

**Choice:** `XcodeGen` (`project.yml`) generates `PadelScore.xcodeproj`.

**Why:** Keeps the multi-target layout reproducible in git without hand-editing `pbxproj`.

## UI labels

**Choice:** Score buttons default to "Us" / "Them". Serve always alternates after each game and during tie-breaks. The serve ball appears on the serving team's button. "Swap sides each game" defaults **off**, so Us/Them stay fixed and the ball moves with the server. When enabled, the point buttons swap after each game so the serving team stays on the left (ball stays left). Users can switch labels to "Serving" / "Receiving" (following the serving team on each button). Games won in the current set appear above the buttons; set wins are omitted from the score page (available on Overview).

**Why:** Fixed button positions are the simpler default for wrist scoring; swapping sides is opt-in when players want Us/Them to follow announcement order (server first). Serve rotation is a scoring rule, not a layout preference.
