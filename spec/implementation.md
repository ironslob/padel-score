# Implementation Specification

**Project:** Padel Score

**Version:** 1.0

---

# 1. Purpose

## Scope

This document defines how the application should be implemented.

It intentionally focuses on engineering guidance rather than user-facing behaviour.

It specifies:

- project organisation
- engineering principles
- implementation strategy
- testing
- state management
- persistence
- coding standards

It does **not** prescribe unnecessary implementation details where Cursor can make sensible engineering decisions.

Where implementation choices are not explicitly defined, Cursor should choose the simplest, most maintainable solution that satisfies the product requirements.

---

# 2. Engineering Principles

The implementation should optimise for:

1. Simplicity
2. Maintainability
3. Testability
4. Reliability
5. Offline-first behaviour

Performance is important but should not come at the expense of clarity.

---

# 3. Implementation Philosophy

The implementation should be split into distinct layers with clear responsibilities.

Business logic should never depend on UI.

UI should never implement business rules.

Persistence should never contain scoring logic.

Networking should never influence scoring behaviour.

Each layer should be independently testable.

---

# 4. Cursor Expectations

Cursor is expected to:

- read every specification before implementation
- understand the product before writing code
- make sensible engineering decisions where appropriate
- document important architectural decisions
- keep implementations simple
- avoid premature optimisation

Cursor should avoid inventing new product features.

---

# 5. Development Order

Implementation should follow the milestones.

Do not jump ahead.

Recommended order:

## Stage 1

Project setup

## Stage 2

Scoring engine

## Stage 3

Persistence

## Stage 4

Watch UI

## Stage 5

Phone UI

## Stage 6

Polish

Future backend work is intentionally excluded.

---

# 6. Project Structure

Recommended structure:

```text
PadelScore/

    WatchApp/

    iPhoneApp/

    Shared/

        Models/

        Scoring/

        Persistence/

        Utilities/

    Tests/

        Unit/

        Integration/

        UI/
```

Minor deviations are acceptable if they improve clarity.

---

# 7. Scoring Engine

The scoring engine is the heart of the application.

It should be implemented before any UI work.

The scoring engine should have:

- no SwiftUI
- no WatchKit
- no UIKit
- no persistence
- no networking

It should operate only on data.

---

# 8. State Machine

The scoring engine should be implemented as a deterministic state machine.

Inputs:

Current state

+

Action

↓

Updated state

Actions include:

- point won
- undo
- finish match
- end early
- discard

The same inputs should always produce the same outputs.

---

# 9. Event Sourcing

The source of truth should be an event stream.

Examples:

```text
MatchStarted

PointWon(Left)

PointWon(Right)

PointWon(Left)

Undo

PointWon(Right)

MatchFinished
```

The current score should be derived from those events.

Caching derived state is encouraged if it improves performance.

Events remain the canonical history.

---

# 10. Undo

Undo should never attempt to manually reverse scoring logic.

Preferred approach:

Restore the previous snapshot.

Alternative:

Replay events excluding the final event.

Either approach is acceptable.

The implementation should favour correctness over cleverness.

---

# 11. Match State

The application should maintain a complete in-memory representation of the current match.

The UI should bind to this state.

Whenever state changes:

- UI updates
- persistence updates
- undo history updates

---

# 12. Persistence Strategy

Persistence should happen automatically.

The user should never manually save.

The current match should survive:

- app restart
- watch restart
- phone restart
- battery interruption

Saving should occur after every meaningful state change.

---

# 13. Local Storage

Version 1 stores everything locally.

Including:

- active match
- completed matches
- scoring events
- undo history

No network dependency.

---

# 14. Match History

Store the complete history.

Do not only store final scores.

Every point should remain available.

This supports future:

- replay
- analytics
- backend sync
- debugging

---

# 15. View Models

View models should:

- expose observable state
- translate user interactions into scoring actions
- coordinate persistence

View models should not implement scoring rules.

---

# 16. UI Responsibilities

Views should:

display state

forward user actions

present navigation

animate changes

trigger haptics

Views should avoid business logic.

---

# 17. Navigation

Navigation should remain shallow.

The active match should consist of horizontal pages.

Avoid deep navigation hierarchies.

Avoid modal flows during play.

---

# 18. Error Handling

Errors should be recoverable.

Examples:

Persistence failure

↓

Retry automatically

Unexpected state

↓

Log

↓

Recover safely

Application crash

↓

Restore match on launch

The user should lose as little work as possible.

---

# 19. Logging

Version 1 should include lightweight structured logging.

Useful events include:

- match started
- point recorded
- undo
- game won
- set won
- match finished
- persistence failure

Avoid excessive logging.

---

# 20. Configuration

Avoid hard-coded values where future configuration is likely.

Examples:

Golden point enabled

Best of three

Games per set

Undo timeout

Version 1 may expose these as constants rather than user settings.

---

# 21. Testing Philosophy

Testing is mandatory.

Business logic should have significantly more tests than UI.

Suggested ratio:

80% business logic

20% UI

---

# 22. Unit Tests

The scoring engine should include comprehensive tests.

Examples:

Love → 15

15 → 30

30 → 40

40 → Game

Deuce

Advantage

Return to deuce

Golden point activation

Golden point winner

Set win

Match win

Undo

End early

Discard

Persistence restoration

---

# 23. Integration Tests

Verify interactions between:

Scoring

↓

Persistence

↓

UI

Examples:

Point scored

↓

Stored

↓

Restored

↓

Displayed

---

# 24. UI Tests

Only critical journeys require UI automation.

Examples:

Start match

Score point

Undo

Finish match

Restore active match

Browse history

---

# 25. Performance

Performance targets:

Point registration should feel immediate.

UI updates should appear instantaneous.

Persistence should not noticeably block interaction.

Optimise only after correctness.

---

# 26. Accessibility

Use native accessibility support.

Buttons should be easily tappable.

Avoid relying solely on colour.

Dynamic type should be respected where practical.

---

# 27. Code Quality

Prefer:

Small files

Small functions

Meaningful names

Composition

Explicit state

Avoid:

Large view files

Massive view models

Hidden state

Complex inheritance

---

# 28. Dependencies

Prefer Apple's frameworks.

Avoid unnecessary third-party libraries.

Introduce dependencies only when they provide significant long-term value.

---

# 29. Documentation

Public types should be documented where useful.

Complex algorithms should explain why rather than what.

Avoid redundant comments.

Good naming is preferred over excessive documentation.

---

# 30. Future Backend Compatibility

Although Version 1 is local-only, implementation should anticipate future synchronisation.

Future backend:

Python

↓

FastAPI

↓

PostgreSQL

↓

Railway

↓

Descope Authentication

Current models should be designed so they can be serialised cleanly.

---

# 31. Decision Log

Where Cursor makes an implementation decision not covered by the specifications, it should document it.

Examples:

Choice of persistence abstraction.

Choice of event representation.

Choice of observable state management.

Choice of project structure.

The goal is to make future iterations easier.

---

# 32. Definition of Done

A milestone is complete only when:

- implementation matches the product specification
- unit tests pass
- integration tests pass
- no significant known defects remain
- code is documented where appropriate
- project builds successfully
- implementation decisions are recorded if they differ materially from the specification

Correctness is more important than feature count.

The application should always remain in a releasable state.
