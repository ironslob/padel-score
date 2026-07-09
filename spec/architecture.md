# Architecture Specification

**Project:** Padel Score

**Version:** 1.0

---

# 1. Purpose

## Scope

This document describes the overall software architecture of the Padel Score application.

It defines:

- major architectural components
- boundaries between components
- ownership of responsibilities
- application state
- persistence architecture
- future backend architecture
- synchronisation strategy

It intentionally avoids prescribing low-level implementation details unless they are architecturally significant.

The architecture should support both the initial offline-only application and future cloud-backed synchronisation without requiring significant redesign.

---

# 2. Architectural Principles

The architecture should satisfy the following principles.

## Offline First

The application must function correctly with no internet connection.

Scoring a match must never depend on:

- network connectivity
- backend availability
- iPhone availability
- CloudKit
- synchronisation

The local device is always authoritative while a match is in progress.

---

## Shared Business Logic

Scoring rules should exist exactly once.

The same implementation should be used by:

- Apple Watch
- iPhone
- future backend validation
- automated tests

There should never be duplicate scoring logic.

---

## Separation of Concerns

The application should be separated into layers.

Each layer has a single responsibility.

Dependencies should always flow downward.

Example:

```
UI

↓

View Models

↓

Application Services

↓

Scoring Engine

↓

Persistence
```

The scoring engine should not know that the UI exists.

---

## Deterministic Behaviour

Given:

- an initial match state
- a sequence of events

the resulting score must always be identical.

This allows:

- replay
- synchronisation
- debugging
- validation
- testing

---

# 3. High-Level Architecture

Version 1 consists of two applications.

```
Apple Watch

↓

Shared Domain Layer

↓

Local Persistence

↑

iPhone
```

No backend exists in Version 1.

---

Future architecture becomes:

```
Apple Watch

↓

iPhone

↓

FastAPI

↓

PostgreSQL
```

The Watch should never communicate directly with the backend.

The iPhone acts as the synchronisation gateway.

---

# 4. Major Components

The application should consist of the following logical components.

## Watch UI

Responsibilities:

- render current match
- capture user input
- display match progress
- display history summaries
- provide haptic feedback

Should not contain business logic.

---

## iPhone UI

Responsibilities:

- browse history
- inspect completed matches
- review active match
- future settings

Should not duplicate scoring behaviour.

---

## View Models

Responsibilities:

- expose observable application state
- coordinate actions
- communicate with services
- update UI

Should remain lightweight.

---

## Application Services

Responsibilities:

- coordinate persistence
- coordinate scoring engine
- restore active match
- expose match history

Should contain workflow logic rather than business rules.

---

## Scoring Engine

The scoring engine is the core of the application.

Responsibilities:

- game scoring
- set scoring
- match scoring
- golden point logic
- undo
- validation

It should have no knowledge of:

- SwiftUI
- persistence
- networking
- Apple Watch
- iPhone

---

## Persistence

Responsibilities:

- save active match
- load active match
- save history
- retrieve history
- persist events

Persistence should remain independent of scoring.

---

# 5. Domain Model

The architecture should revolve around a small number of core domain concepts.

Primary entities include:

- Match
- Set
- Game
- Point Event

Supporting entities include:

- Match Status
- Match Result
- Team
- Match Settings

Additional entities should only be introduced when they provide meaningful value.

---

# 6. Match Lifecycle

A match transitions through a defined lifecycle.

```
Not Started

↓

In Progress

↓

Completed
```

Alternative terminal states:

```
Ended Early

Discarded
```

Transitions should be explicit.

---

# 7. Event Model

The application should treat every user action as an immutable event.

Examples:

```
MatchStarted

PointWon(Left)

PointWon(Right)

Undo

MatchFinished
```

Events represent facts.

Events should never be edited.

---

# 8. Derived State

Current score is derived from the event stream.

Derived information includes:

- current game
- current set
- current match
- golden point status
- elapsed duration

The application may cache derived state for performance.

The event history remains authoritative.

---

# 9. Undo Architecture

Undo should operate on application history rather than score manipulation.

Preferred behaviour:

```
Event Stream

↓

Remove final action

↓

Recalculate state
```

Alternative implementations using snapshots are acceptable if behaviour remains identical.

---

# 10. Persistence Model

Persistence consists of two logical areas.

## Active Match

Stores:

- current state
- event history
- temporary metadata

Only one active match should exist.

---

## Match Archive

Stores:

- completed matches
- ended early matches
- event history
- metadata

Matches should remain immutable after completion.

---

# 11. State Ownership

Only one component should own application state.

Recommended ownership:

```
Application Service

↓

Observable View Model

↓

SwiftUI Views
```

Views should never own business state.

---

# 12. Communication

Communication between layers should be unidirectional.

```
User Action

↓

View Model

↓

Application Service

↓

Scoring Engine

↓

Persistence

↓

Updated State

↓

View Model

↓

UI
```

Avoid circular dependencies.

---

# 13. Error Recovery

Errors should remain local whenever possible.

Examples:

Persistence failure

↓

Retry

↓

Notify if necessary

Backend failure (future)

↓

Remain offline

↓

Retry later

The user should always be able to continue scoring.

---

# 14. Synchronisation Strategy

Version 1 performs no synchronisation.

Future synchronisation should be asynchronous.

The application should never block the user while waiting for uploads or downloads.

---

# 15. Future Backend Architecture

The long-term backend consists of:

```
FastAPI

↓

Business Services

↓

PostgreSQL
```

Responsibilities include:

- authentication
- match storage
- synchronisation
- history
- statistics
- validation

The backend should never become responsible for live scoring.

Scoring remains on-device.

---

# 16. Authentication

Version 1 has no authentication.

Future versions should use:

Descope

Authentication should remain independent of scoring.

A user should always be able to score a match before synchronisation occurs.

---

# 17. API Design Principles

Future APIs should be resource-oriented.

Examples include:

- Matches
- Match Events
- Players
- Statistics

The backend should accept complete event histories rather than only final scores.

---

# 18. Database Principles

Future PostgreSQL schema should prioritise:

- immutable history
- auditability
- efficient querying
- future analytics

Raw match events should be retained.

Aggregated statistics can be derived later.

---

# 19. Conflict Resolution

Future synchronisation should assume:

The watch is authoritative during an active match.

Conflicts should be resolved through event history rather than overwriting state.

This is one of the reasons for storing immutable events.

---

# 20. Scalability

Although Version 1 is intentionally small, the architecture should comfortably support:

- thousands of matches
- multiple devices
- cloud sync
- statistics
- AI analysis
- replay
- coaching features

without major redesign.

---

# 21. Extension Points

The architecture should make future additions straightforward.

Examples include:

- configurable scoring rules
- tie-break variants
- player names
- tournaments
- leagues
- doubles partnerships
- wearable complications
- Apple Health integration

These should be additive rather than requiring architectural changes.

---

# 22. Architectural Constraints

Avoid:

- business logic inside views
- duplicated scoring rules
- tightly coupled persistence
- backend-dependent scoring
- mutable event history
- circular dependencies

These constraints exist to keep the architecture maintainable as the project grows.

---

# 23. Architectural Decision Making

Where the specifications do not dictate a specific design, Cursor should choose the solution that:

1. preserves separation of concerns
2. minimises complexity
3. improves maintainability
4. supports future synchronisation
5. remains easy to test

The simplest architecture that satisfies these principles should always be preferred over a more elaborate solution.
