# Product Specification

**Project:** Padel Score

**Version:** 1.0

**Status:** Draft

---

# 1. Purpose

## Scope

This document describes the product requirements for the Padel Score application.

It defines:

- product goals
- user experience
- supported functionality
- business rules
- scoring behaviour
- user interface behaviour
- milestones

This document intentionally does **not** specify implementation details unless they materially affect user experience.

Implementation decisions are described in the accompanying implementation and architecture specifications.

Where behaviour is not explicitly defined, sensible engineering decisions should be made that best satisfy the product goals.

---

# 2. Vision

Padel Score is an Apple Watch-first scoring application designed specifically for tracking padel matches.

The primary goal is to make score keeping require almost zero mental effort while playing.

The application should feel faster than asking another player for the score and significantly easier than remembering it yourself.

The Apple Watch is the primary product.

A Garmin Connect IQ port ships in parallel. Scoring behaviour must stay identical.

The iPhone exists to support the Watch experience by providing history, review and future synchronisation.

---

# 3. Product Principles

Every product decision should support these principles.

## 3.1 Apple Watch First

The watch is the primary experience.

If a design decision benefits the watch at the expense of the phone, the watch should be prioritised.

---

## 3.2 Lowest Possible Cognitive Load

Users are:

- moving
- distracted
- tired
- often talking

The interface should require almost no thinking.

The user should always know:

- current score
- what button to press next

without searching the screen.

---

## 3.3 Fast Interaction

Recording a point should take approximately one second.

The user should never navigate menus while scoring.

---

## 3.4 Offline First

Scoring a match must never depend on:

- internet
- backend
- cloud sync
- nearby phone

The application should always function normally.

---

## 3.5 Recover From Mistakes

Incorrect taps will happen.

Undo should be fast and obvious.

Correcting a mistake should be significantly easier than manually reconstructing the score.

---

## 3.6 History Matters

Every completed match should be retained.

The complete scoring history should be preserved.

Future versions should be capable of replaying an entire match from recorded events.

---

# 4. Product Goals

The application should allow a player to:

- start a match in seconds
- keep score during play
- finish a match
- stop a match early
- review previous matches

without requiring another device.

---

# 5. Out of Scope

Version 1 intentionally excludes:

- player rankings
- tournaments
- leagues
- social features
- statistics
- AI analysis
- live sharing
- Siri integration
- coaching

The objective is an excellent scoring application.

---

# 6. Supported Platforms

## Version 1

Primary:

- Apple Watch
- Garmin touchscreen watches (Connect IQ)

Secondary:

- iPhone companion

No iPad.

No Mac.

No Android.

---

# 7. User Flow

The complete V1 experience should be:

```
Open Watch App

↓

Start Match

↓

Play

↓

Record Points

↓

Game Ends

↓

Set Ends

↓

Match Ends

↓

View History on Phone
```

Nothing more should be required.

---

# 8. Match Lifecycle

Every match progresses through these states.

```
Not Started

↓

In Progress

↓

Completed
```

Alternative endings:

```
In Progress

↓

Ended Early
```

or

```
In Progress

↓

Discarded
```

---

# 9. Starting a Match

If no active match exists the watch should display a primary start action.

```
Start Match
```

Starting a match always tries to start a Health workout so Padel Score can return when the player raises their wrist. If another app already owns the workout session, the watch prompts to continue without a workout (wrist raise usually will not reclaim the app) or cancel so the other workout can be ended first.

Default settings:

- Best of three sets
- First to six games
- Win by two games
- Tie-break at 6–6 (first to 7 points, win by 2)
- Tie-break serve rotates every 2 points after the opening point; change sides every 6 points
- Golden point at deuce
- Standard scoring
- Warm-up before the first serve (on, no time limit)

Starting a match should remain fast and require no nested configuration.

When warm-up is on, starting a match starts the Health workout when possible and shows a timer. The player taps Play when ready. An optional time limit can auto-advance. Warm-up happens only before the match, never between sets. Warm-up time is included in the Health workout and in match elapsed time.

When warm-up is off, the watch asks who is serving immediately after Start Match.

From warm-up or the opening “who is serving?” prompt, Back returns to the start screen and discards the match. Nothing has been scored yet, so there is no history to keep. Between sets the serve prompt has no Back — a server still has to be chosen.

---

# 10. Active Match

During a match the watch should present three horizontally swipeable screens, landing on the score screen.

## Screen 1

Current match summary (sets, elapsed).

## Screen 2

Current scoring.

## Screen 3

Actions.

No nested menus.

---

# 11. Score Screen

The score screen is the most important screen in the application.

It should display the current game score and games in the current set. Match set wins live on the summary screen.

Below this should be two large buttons.

```
Us
```

```
Them
```

Pressing either immediately awards a point.

---

# 12. Score Orientation

The application always tracks who is serving and rotates serve after each game (and during tie-breaks) per padel rules.

The serve indicator (tennis ball) appears on the button for the side that is serving.

**Swap sides each game** (defaults off) controls button layout only:

- **Off:** Us and Them stay where they were chosen at match start. The serve indicator moves to whichever team is serving.
- **On:** After each game, the point buttons swap so the serving team stays on the **left** (receiving on the right). The serve indicator stays on the left.

Default labels are Us / Them. Serving / Receiving labels are available as an alternative and follow whichever team is serving on each button.

---

# 13. Standard Scoring

Version 1 supports:

```
0

15

30

40

Deuce

Advantage

Game
```

Users never manually calculate scores.

The application performs all score progression automatically.

---

# 14. Scoring at Deuce

The way a game is resolved at 40-40 is a user setting with three options.

**Regular** — traditional advantage scoring. Advantage repeats until one side
wins two points in a row.

```
40-40 → Advantage → Back to Deuce → Advantage → … → Game
```

**Silver point** — one advantage is played. If it is broken, the next point
decides the game.

```
40-40 → Advantage → Back to Deuce → Silver Point → Next Point Wins
```

**Golden point** (default) — no advantage phase at all. The first point at
40-40 decides the game. This is the format used by the FIP and Premier Padel.

```
40-40 → Golden Point → Next Point Wins
```

The decisive point should become clearly visible on screen, named for the
format in play.

Example:

```
Golden Point

Next point wins
```

Note: versions before this setting existed shipped a single "Golden point"
toggle whose behaviour was in fact silver point. Matches archived under that
toggle decode as silver point so their scorelines stay faithful to how they
were played.

---

# 15. Undo

After recording a point the application enters a temporary undo state.

Undo should remain available for approximately three seconds.

Example:

```
Undo (3)

Undo (2)

Undo (1)
```

If Undo is selected:

- the previous score is restored
- the countdown disappears
- normal scoring resumes

After the timeout expires the point becomes part of permanent match history.

When a game ends, a brief summary offers Undo and Next. It continues on its own if nobody taps.

When a set ends and the match is still in progress, the summary stays until the player chooses. Buttons stay normal size and scroll, with the most likely actions first:

```
Next set

New serve

Undo

End match
```

New serve is available while the new set has not been played into. End match requires confirmation and keeps the current score.

---

# 16. Match Screen

The second screen displays current match status.

Example:

```
Current Set

5 – 4

Current Match

1 – 0

Elapsed

48 min
```

If golden point is active this should also be displayed.

No editing is possible on this screen.

---

# 17. Actions Screen

The third screen contains administrative actions.

Actions include:

```
Undo Last Point

New Serve

Finish Match

End Match Early

Discard Match
```

New Serve is available between sets while the new set is untouched. Settings (labels, swap sides, deuce format, match length) live on the same screen.

Any destructive action requires confirmation.

Discarding removes the match completely.

Ending early preserves history.

---

# 18. Completing a Match

When a match completes naturally:

Display a completion screen.

Example:

```
Match Complete

Won

6-4

6-3
```

Offer:

```
Done
```

Returning to the home screen should leave no active match.

---

# 19. Ending Early

Some matches finish because:

- court booking expires
- injury
- weather
- retirement
- agreement between players

Version 1 supports ending a match early.

The current score should be retained exactly as played.

History should clearly indicate:

```
Ended Early
```

---

# 20. Discarding a Match

Discarding should only be used when:

- match started accidentally
- scoring became unusable
- user wishes to abandon history

Confirmation is required.

Discarded matches are not shown in history.

---

# 21. Match History

Every completed match should be stored.

History should include:

- start time
- finish time
- duration
- completion status
- final score
- complete scoring history

No data should be intentionally discarded.

Future versions will rely on this history.

---

# 22. iPhone Companion

The iPhone application exists primarily for review.

Version 1 allows users to:

- browse previous matches
- inspect completed matches
- view in-progress match
- add notes
- delete matches from history

The iPhone does **not** score matches during Version 1.

---

# 23. Accessibility

Buttons should be large.

Text should remain readable outdoors.

Interactions should require minimal precision.

The application should remain usable while moving.

---

# 24. Error Recovery

The application should recover gracefully from:

- app restart
- watch restart
- battery interruption

The current match should be restored automatically whenever possible.

The user should not lose progress.

---

# 25. Future Product Direction

The architecture should support future additions including:

- FastAPI backend
- PostgreSQL storage
- Railway deployment
- Descope authentication
- cloud synchronisation
- player profiles
- statistics
- match replay
- AI insights
- tournaments
- leagues

Version 1 should not include these features, but should avoid decisions that would make them difficult to add later.

---

# 26. Milestones

## Milestone 1

Watch scoring MVP.

Deliver:

- Start match
- Score points
- Game scoring
- Set scoring
- Match scoring
- Deuce format (regular / silver / golden point)
- Undo
- Finish match
- End early
- Local persistence

---

## Milestone 2

Companion iPhone application.

Deliver:

- Match history
- Match detail
- Restore active match
- Improved polish
- Accessibility improvements

---

## Milestone 3

Backend.

Deliver:

- FastAPI
- PostgreSQL
- Railway
- Descope authentication
- Match synchronisation

---

## Milestone 4

Statistics.

Deliver:

- Win percentage
- Match trends
- Golden point record
- Average duration
- Streaks
- Insights

---

# 27. Success Criteria

Version 1 is considered successful when a user can:

1. Open the Watch app.
2. Start a match with one tap.
3. Record an entire match without confusion.
4. Recover from mistakes using Undo.
5. End the match.
6. View the completed match on their iPhone.

If these tasks feel effortless, the product has achieved its primary goal.
