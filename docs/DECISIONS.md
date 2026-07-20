# Implementation Decisions

Documented decisions that were not fully prescribed by `/spec`.

## Persistence: JSON files instead of SwiftData

**Choice:** `FileMatchStore` writes Codable `MatchState` JSON under Application Support.

**Why:** Simplifies unit testing with an in-memory store, keeps the event stream trivially serializable for WatchConnectivity and a future FastAPI API, and avoids SwiftData/WatchOS edge cases for V1.

## Watch ↔ iPhone sync: WatchConnectivity application context

**Choice:** Watch pushes active match + archive via `WCSession.updateApplicationContext` (and `sendMessage` when reachable). iPhone applies remote snapshots; Watch does not accept phone-authored score updates.

**Why:** Matches the architecture rule that the Watch is authoritative during live scoring. No CloudKit in V1.

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

**Choice:** Score buttons default to "Us" / "Them" labels, oriented so the **serving team is always on the left** (receiving on the right). The serve ball stays on the left; "Swap sides each game" defaults **off**, so Us/Them stay where they were chosen. When enabled, the point buttons swap after each game so Us/Them follow the server. Users can switch labels to "Serving" / "Receiving" (also always left/right when a server is known). Games won in the current set appear above the buttons; set wins are omitted from the score page (available on Overview).

**Why:** Matches court announcement order (server first) and product score-screen orientation. Fixed button positions are the simpler default for wrist scoring; swapping sides is opt-in when players want Us/Them to follow the server.
