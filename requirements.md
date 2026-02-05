# Requirements
## Overview
- IncidentHub is a lightweight incident management system used by engineering teams
- It can be used to report, assign, and resolve production incidents across multiple services
- It provides an auditable incident timeline, role-based access control, and basic notifications for critical incidents


## Goals (what success looks like)
- Engineers can create incidents in < 30 seconds and immediately see them in a list
- Incident lifecycle is a consistent aud auditable (who changed what, when)
- Critical incidents trigger notifications reliably (at least once delivery)
- System is easy to run locally (docker compose) and has CI pipelines (build, test, image)

## Non-Goals (out of scope)
- Full on-call scheduling / rotations (PagerDuty-like)
- Complex SLA reporting dashboards
- Multi-tenant SaaS billing, advanced org structures
- Real email provider integration (can be mocked/logged)


# User Roles
## Admin
- manage users
- view everything
- override assignments/status

## Engineers
- create/acknowledge/update incidents
- add comments
- assign incidents

## Viewer
- read-only access to incidents and timeline




# Core Entities
## Incident
- id (uuid)
- title (string, required, max 140)
- description (text, required)
- severity (LOW, MEDIUM, HIGH, CRITICAL)
- serviceName (string, required)
- status (OPEN, ACKNOWLEDGED, IN_PROGRESS, RESOLVED, CLOSED)
- createdAt, updatedAt
- createdBy (user id)
- assigned to (user id, optional)

## IncidentComment
- id (uuid)
- incidentId
- authorId
- message (text, required)
- createdAt



## IncidentEvent (audit timeline)
Represents immutable events:
- INCIDENT_CREATED
- INCIDENT_CRITICAL
- STATUS_CHANGED
- ASSIGNED
- UNASSIGNED
- COMMENT_ADDED
Fields:
- id
- incidentId
- type
- payload (JSON)
- actorId
- createdAt


## NotificationOutbox
- id (uuid)
- type (IncidentEvent etc.)
- payload (JSON)
- status (PENDING, SENT, FAILED)
- attempts (int)
- createdAt, updatedAt


 Audit role just so it can audit anything?
Audit servie:
- scan data
- info
- who did what and when
etc...

# System Architecture
- incident service (Spring Boot): incidents API + DB + audit timeline + outbox writes
- auth service (Spring Boot): users + roles + JWT issuance (can be merged into one service if desired) - or other better alternatives like OAuth2, Keycloak locally
- notification-worker (Spring Boot or simple module): polls outbox and sends notifications (log/webhook)
- Optional: API-Gateway later; can expose services directly
- audit service: who did what and when, chronologically; all CRITICAL incidents since last week; who closed the most incidents; how long has it been OPEN?; incidents per ServiceName / day; MTTA, MTTR, heatmap

- Database: PostgreSQL
- Migrations: Flyway (required) ???
- Local Runtime: docker compose
- CI: build, tests, docker image


# API Requirements
- RESTful endpoints, JSON payloads
- Validation errors return consistent error format
- Pagination for list endpoints
- Filtering by status, severity, serviceName, dateRange
- Authentication viat JWT
- Authorization by role









# Epics & User Stories
## EPIC 1 — Project Setup & Local Run
### US-1.1 Repository structure
**As a developer**, I want a clear multi-module repository structure, so I can build and run components consistently.

**Acceptance Criteria**
- Repository contains modules for incident-service, auth-service (or combined), notification-worker
- Standardized formatting/linting configured (Spotless/Checkstyle optional)

**DoD**
- `./mvnw test` (or gradle) runs successfully.

### US-1.2 Local environment via Docker Compose
**As a developer**, I want to run the system locally with one command.

**Acceptance Criteria**
- `docker-compose up` starts PostgreSQL and required services
- Services start with sensible defaults (dev profile)
- Readme includes steps

**DoD**
- A new developer can run locally in < 10 minutes using README.


## EPIC 2 — Authentication & RBAC
### US-2.1 User login (JWT)
**As a user**, I want to log in and receive a JWT, so I can call protected APIs.

**Acceptance Criteria**
- `POST /auth/login` returns JWT for valid credentials
- Invalid credentials return 401
- JWT includes roles

### US-2.2 Role-based access control
**As an admin**, I want endpoints protected by role, so viewers cannot modify incidents.

**Acceptance Criteria**
- VIEWER: can only read
- ENGINEER: can create/update incidents, comment, assign
- ADMIN: can do everything + user management endpoints (optional in v1)

---

# EPIC 3 — Incident CRUD & Lifecycle
### US-3.1 Create incident
**As an engineer**, I want to create an incident with severity and serviceName.

**Acceptance Criteria**
- `POST /incidents` creates incident in status OPEN
- Validations: title/description/serviceName required, severity required
- Emits audit event INCIDENT_CREATED

### US-3.2 List incidents with pagination & filters
**As a viewer**, I want to browse incidents and filter them.

**Acceptance Criteria**
- `GET /incidents?page=&size=` returns paginated list
- Filters: `status`, `severity`, `serviceName`, `createdFrom`, `createdTo`
- Sorted by `createdAt desc` by default

### US-3.3 Get incident details
**As a viewer**, I want incident details including current assignment and last update.

**Acceptance Criteria**
- `GET /incidents/{id}` returns incident DTO

### US-3.4 Change incident status with workflow rules
**As an engineer**, I want to change status following a consistent workflow.

**Acceptance Criteria**
- Allowed transitions:
  - OPEN -> ACKNOWLEDGED
  - ACKNOWLEDGED -> IN_PROGRESS
  - IN_PROGRESS -> RESOLVED
  - RESOLVED -> CLOSED
- Invalid transitions return 409 with reason
- Emits audit event STATUS_CHANGED (old/new)

### US-3.5 Assign/Unassign incident
**As an engineer**, I want to assign an incident to a user.

**Acceptance Criteria**
- `PUT /incidents/{id}/assignee` assigns by userId
- `DELETE /incidents/{id}/assignee` unassigns
- Emits audit event ASSIGNED/UNASSIGNED

---

# EPIC 4 — Comments & Timeline (Audit)
### US-4.1 Add comment
**As an engineer**, I want to add comments for coordination.

**Acceptance Criteria**
- `POST /incidents/{id}/comments` adds comment
- Emits audit event COMMENT_ADDED

### US-4.2 Read timeline
**As a viewer**, I want to see a chronological timeline of actions.

**Acceptance Criteria**
- `GET /incidents/{id}/timeline` returns events ordered by createdAt asc
- Includes actor, event type, and payload

---

# EPIC 5 — Persistence & Data Quality
### US-5.1 DB migrations (Flyway)
**As a developer**, I want database changes versioned.

**Acceptance Criteria**
- Flyway enabled
- Initial migration creates all tables
- Subsequent changes are additive migrations

### US-5.2 Avoid N+1 and provide efficient reads
**As a developer**, I want incident list/details to be performant.

**Acceptance Criteria**
- No obvious N+1 on comments/timeline
- Uses DTO projections/entity graphs/fetch join where appropriate
- Adds indexes on commonly filtered fields (status, severity, serviceName, createdAt)

---

# EPIC 6 — Notifications (Reliable)
### US-6.1 Outbox write on critical incidents
**As a stakeholder**, I want CRITICAL incidents to trigger notifications reliably.

**Acceptance Criteria**
- When incident created with severity CRITICAL (or changed to CRITICAL), a NotificationOutbox row is created
- Outbox record is created in the same transaction as the incident update

### US-6.2 Notification worker sends webhook/log
**As a team**, we want a basic notification channel.

**Acceptance Criteria**
- Worker polls outbox every N seconds
- Sends webhook to configured URL OR logs a message (v1 acceptable)
- Updates outbox status to SENT/FAILED and increments attempts
- Retries with backoff up to max attempts

---

# EPIC 7 — Observability
### US-7.1 Health and metrics
**As an operator**, I want health endpoints and basic metrics.

**Acceptance Criteria**
- Actuator enabled with `/actuator/health`
- Structured logs include correlation/request id (if implemented)

---

# EPIC 8 — CI/CD
### US-8.1 CI pipeline (build, test, image)
**As a developer**, I want CI to validate changes automatically.

**Acceptance Criteria**
- Pipeline runs:
  - unit tests
  - integration tests (Testcontainers for Postgres where appropriate)
  - docker image build
- Artifacts stored (image pushed to registry if configured)

---

## Definition of Done (Global)
- Code compiles and tests pass locally and in CI
- API endpoints documented (OpenAPI/Swagger) or minimal docs in README
- Error handling consistent
- Security enforced by role
- Migrations and docker-compose kept up to date