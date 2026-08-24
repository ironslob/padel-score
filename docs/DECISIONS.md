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

**Choice:** Undo removes the last `pointWon` event and replays the stream. After a point on the score screen, a 3-second clockwise outline animates on that side’s button; tapping the same button again cancels the point. Actions screen allows undo anytime while in progress.

**Why:** Keeps undo fast on the tiny Watch score surface without a separate Undo control, while Actions still covers recovering older mistakes. Replay keeps behaviour identical to event sourcing.

## Choosing a new server at the changeover

**Choice:** The set summary waits to be tapped through — unlike the game one, it has no countdown. Buttons stay normal size and scroll in likelihood order: Next set, New serve (while the new set is untouched), Undo, End match. The Actions screen repeats New serve for as long as the new set is untouched. New serve puts the match back to "Who's serving?" instead of carrying the rotation on. `requestServerSelection` records no event of its own — it only re-arms `needsServerSelection`, and replay accepts a `serverSelected` event at a set boundary even when the match was not waiting for one. End match uses `finishMatch` with confirmation, the same as the Actions screen.

**Why:** Players swap ends between sets and often rearrange who serves, which the existing `askServeAtSetStart` preference only covers by asking every single time. Social and continuous matches also often stop after a set, so End match belongs on that screen rather than only behind a swipe to Actions. The three-second quick-undo window is far too short to survive a changeover, so auto-advancing would have hidden the choices before anyone reached their wrist. Shrinking buttons to keep every action above the fold made them harder to hit; scrolling the less likely ones is the better trade. Storing the New serve request as an event would need a new `MatchEventKind`, which an older build sharing the archive could not decode; the choice that follows is the fact worth keeping, and the set boundary it belongs to is already derivable from the stream. Anywhere other than a set start the stored choice is ignored on replay, so undoing the set-winning point drops a server picked for a set that is no longer over rather than applying it mid-game.

## Golden point house rule

**Choice:** Three deuce formats. **Golden point** (default, FIP): 40-40 is immediately decisive — no advantage. **Silver point:** one advantage is played; if it is broken, the next point wins. **Regular:** advantage repeats until one side wins by two. Versions before this setting existed shipped a "Golden point" toggle that actually played silver point; archived matches decode as silver so their scorelines stay faithful.

**Why:** Exactly as specified in `spec/product.md` §14.

## Finish Match vs End Early

**Choice:** Finish with a natural match winner marks `completed`. Finish without a winner marks `endedEarly`, matching event replay. Explicit End Early always marks `endedEarly`. Discard is not archived.

**Why:** Product distinguishes completed, ended early, and discarded terminal states.

## Project generation

**Choice:** `XcodeGen` (`project.yml`) generates `PadelScore.xcodeproj`.

**Why:** Keeps the multi-target layout reproducible in git without hand-editing `pbxproj`.

## UI labels

**Choice:** Score buttons default to "Us" / "Them". Serve always alternates after each game and during tie-breaks. The serve ball appears on the serving team's button. "Swap sides each game" defaults **off**, so Us/Them stay fixed and the ball moves with the server. When enabled, the point buttons swap after each game so the serving team stays on the left (ball stays left). Users can switch labels to "Serving" / "Receiving" (following the serving team on each button). Games won in the current set appear above the buttons; set wins are omitted from the score page (available on Overview).

**Why:** Fixed button positions are the simpler default for wrist scoring; swapping sides is opt-in when players want Us/Them to follow announcement order (server first). Serve rotation is a scoring rule, not a layout preference.

## Garmin scoring parity

**Choice:** Garmin’s Monkey C engine mirrors Apple for serve rotation at set and tie-break boundaries, New Serve at changeover, mid-match deuce format changes, match-length / ask-serve / Us-Them settings, pre-match warm-up, destructive-action confirmation, and the game/set interstitial.

**Still Garmin-only gaps:** HealthKit / workout recording, phone companion sync, complications, and Live Activities — blocked by Connect IQ APIs. See `garmin/README.md`. Warm-up on Garmin is the same elapsed timer and Play action as Apple; it is not recorded as a FIT activity.

## Pre-match warm-up

**Choice:** Warm-up is a `needsWarmUp` flag on match state, not a new event kind. Completing it records nothing; elapsed time is `now - startedAt`. An optional minute limit can auto-advance; the default is no limit. Replay restores the flag the same way it restores a New Serve prompt. It is armed only at match start, never at set boundaries.

The HealthKit workout still starts once in `startMatch` and ends once when the match completes, ends early, or is discarded. Warm-up, scoring, and set changeovers share that single session. Pause/resume is only the system workout control, not an automatic split between games or sets.

**Why:** Older builds sharing the archive cannot decode a new event kind. A flag matches New Serve, and one workout per match is what Apple Health already recorded.

## Health workout ownership

**Choice:** Start Match always tries to start a HealthKit workout. There is no home-screen or Settings choice between “Track as workout” and “Score only”. If another app already owns the session, the watch prompts to continue without a workout or cancel the match start. The next Start Match tries again.

**Why:** HealthKit has no API to detect another session in advance, and owning the workout is what makes wrist-raise return to Padel Score. Asking every time added a control most starts do not need. Garmin has no equivalent; it cannot start a HealthKit session.

