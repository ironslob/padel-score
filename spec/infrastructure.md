# Infrastructure Specification

**Project:** Padel Score

**Version:** 1.0

---

# 1. Purpose

## Scope

This document defines the infrastructure, tooling and operational environment for the Padel Score project.

It covers:

- technology choices
- project configuration
- build tooling
- dependency management
- testing infrastructure
- version control
- CI/CD
- future deployment architecture

Version 1 is intentionally simple.

Infrastructure should support rapid development while providing a clean migration path towards cloud synchronisation in future milestones.

---

# 2. Guiding Principles

Infrastructure should prioritise:

1. Simplicity
2. Reliability
3. Fast iteration
4. Low operational overhead
5. Future extensibility

Avoid introducing infrastructure before it is needed.

---

# 3. Version 1 Technology Stack

## Apple Applications

Language

- Swift

Frameworks

- SwiftUI
- Foundation
- SwiftData (preferred)
- Combine and/or Observation where appropriate

Platforms

- watchOS
- iOS

Development Environment

- Xcode (latest stable)

No third-party UI frameworks should be introduced without a compelling reason.

---

# 4. Local Persistence

Version 1 is entirely on-device.

Preferred storage:

- SwiftData

Alternative (acceptable if justified):

- Core Data

Persistence must support:

- active match restoration
- completed match history
- event history
- future migration to cloud synchronisation

---

# 5. Future Backend Stack

Backend is **not** part of Version 1.

When introduced, the backend should use the same technology stack as the user's existing projects.

Language

- Python

Framework

- FastAPI

Database

- PostgreSQL

ORM

- SQLAlchemy 2.x

Migrations

- Alembic

Authentication

- Descope

Hosting

- Railway

The backend should expose REST APIs initially. Future GraphQL or WebSocket support can be considered if required.

---

# 6. Backend Responsibilities

The backend should eventually provide:

- user authentication
- device registration
- match synchronisation
- match history
- statistics
- analytics
- backup

The backend should **not** become responsible for live scoring.

Live scoring always remains local to the device.

---

# 7. Repository Structure

Recommended repository layout:

```text
/spec

/watch

/iphone

/shared

/backend (future)

/docs

/scripts
```

The `/spec` directory is the authoritative source of project requirements.

---

# 8. Specification Workflow

Before implementing any feature, Cursor should:

1. Read every file within `/spec`.
2. Understand the relevant milestone.
3. Produce a short implementation plan.
4. Implement only the agreed scope.

If implementation uncovers ambiguity, Cursor should make a reasonable engineering decision and document it rather than blocking progress.

---

# 9. Source Control

Git should be used.

Recommended branching strategy:

- `main` — always releasable
- short-lived feature branches
- merge via pull request where practical

Commits should remain small and focused.

Avoid mixing unrelated changes.

---

# 10. Build Configuration

The project should compile cleanly with:

- no warnings
- no failing tests
- no unused code generated during implementation

Warnings should generally be treated as defects.

---

# 11. Dependency Management

Prefer Apple frameworks.

Before adding a dependency, consider:

- Does Apple already provide this?
- Does it materially reduce complexity?
- Will it still be appropriate in two years?

Avoid introducing dependencies simply because they are popular.

---

# 12. Code Style

Prefer consistency over personal preference.

General guidance:

- meaningful names
- small files
- small functions
- explicit state
- composition over inheritance
- immutable values where practical

Formatting should be automated wherever possible.

---

# 13. Testing Strategy

The project should contain three categories of tests.

## Unit Tests

Highest priority.

Focus on:

- scoring engine
- event replay
- undo
- persistence

Business logic should have comprehensive coverage.

---

## Integration Tests

Verify interactions between:

- scoring engine
- persistence
- application services

Focus on realistic workflows rather than isolated functions.

---

## UI Tests

Cover only critical user journeys.

Examples:

- start match
- record point
- undo
- finish match
- restore active match
- browse history

Avoid excessive UI automation.

---

# 14. Continuous Integration

Every commit should automatically:

- build the project
- execute unit tests
- execute integration tests
- report failures

Future additions may include:

- linting
- formatting checks
- UI tests on pull requests

CI should remain fast enough to encourage frequent commits.

---

# 15. Logging

Version 1 requires lightweight structured logging.

Useful events include:

- application launch
- match started
- point recorded
- undo
- match completed
- persistence failures

Avoid excessive logging that obscures meaningful information.

---

# 16. Error Reporting

Version 1 does not require remote crash reporting.

Future options may include:

- Sentry
- Firebase Crashlytics

This decision should be deferred until cloud infrastructure exists.

---

# 17. Security

Version 1 stores only local match data.

No sensitive personal information is expected.

Future backend design should assume:

- encrypted transport (HTTPS)
- authenticated API requests
- secure token storage
- least-privilege database access

---

# 18. Performance Targets

The application should feel instantaneous.

Indicative goals:

- point registration: immediate
- UI updates: immediate
- match restoration: under one second
- history loading: effectively instant for typical usage

Optimise only after correctness.

---

# 19. Future Cloud Synchronisation

Cloud synchronisation will be introduced in a later milestone.

Requirements:

- offline-first
- background synchronisation
- retry failed uploads
- event-based synchronisation
- conflict resolution using immutable event history

The user should never be prevented from recording points due to synchronisation issues.

---

# 20. Operational Philosophy

Version 1 should have zero operational dependencies.

The application should continue functioning if:

- there is no internet connection
- Railway is unavailable
- PostgreSQL is unavailable
- authentication services are unavailable

The backend should enhance the product, not enable it.

---

# 21. Definition of Infrastructure Done

Infrastructure for a milestone is considered complete when:

- the project builds successfully
- all automated tests pass
- dependencies are documented
- project structure remains consistent
- no unnecessary infrastructure has been introduced
- future migration paths remain clear

Infrastructure should always support the product, never drive it.
