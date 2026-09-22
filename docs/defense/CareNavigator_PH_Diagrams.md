# CareNavigator PH - Mermaid Diagrams

These diagrams are source-controlled Mermaid definitions for the current CareNavigator PH architecture. In VS Code, open Preview (`Ctrl+Shift+V`) with a Mermaid Markdown extension installed, or open the individual `.mmd` files.

## Updated System Architecture

```mermaid
%% Source: system_architecture.mmd
flowchart TB
    Actors[Guest, Patient, Doctor, Hospital Admin, Super Admin] --> Flutter[Flutter mobile and web client]
    Flutter --> UI[Feature screens and shared widgets]
    UI --> Router[GoRouter role guards]
    UI --> State[Riverpod state and realtime streams]
    State --> Repo[Typed Dart repositories]
    Repo --> Auth[Supabase Auth]
    Repo --> API[PostgREST and RPC]
    Repo --> Storage[Private Storage]
    API --> DB[(PostgreSQL plus RLS)]
    DB --> Realtime[Realtime]
    Realtime --> State
    Edge[Edge Functions] --> DB
    Edge --> Groq[Groq AI]
    Edge --> SMTP[Gmail SMTP]
    Flutter --> Jitsi[Jitsi]
    Flutter --> Maps[OpenStreetMap and OSRM]
```

## Updated End-to-End System Flow

```mermaid
%% Source: system_flowchart.mmd
flowchart LR
    A[Discover care] --> B{Need guidance?}
    B -->|Yes| C[Safety-aware care assistant]
    B -->|No| D[Choose facility and schedule]
    C -->|Emergency| E[Immediate escalation]
    C -->|Non-emergency| D
    D --> F[Verified guest request or patient booking]
    F --> G[Consultation]
    G --> H[Structured records, prescriptions, and labs]
    H --> I[Private files, reminders, and follow-up]
```

## Conceptual Database ERD

The complete editable ERD is in `database_erd.mmd`. It emphasizes the main identity, hospital, scheduling, cross-hospital authorization, clinical-record, and communication relationships used by the application.

```mermaid
%% Compact view; see database_erd.mmd for fields.
erDiagram
    USERS ||--o| PATIENTS : owns
    USERS ||--o| DOCTORS : owns
    HOSPITALS ||--o{ HOSPITAL_DEPARTMENTS : contains
    HOSPITALS ||--o{ DOCTOR_HOSPITAL_EMPLOYMENTS : employs
    DOCTORS ||--o{ DOCTOR_HOSPITAL_EMPLOYMENTS : serves_at
    PATIENTS ||--o{ CONSULTATIONS : attends
    DOCTORS ||--o{ CONSULTATIONS : conducts
    HOSPITALS ||--o{ CONSULTATIONS : hosts
    CONSULTATIONS ||--o{ MEDICAL_RECORDS : produces
    CONSULTATIONS ||--o{ PRESCRIPTIONS : produces
    CONSULTATIONS ||--o{ LABORATORY_REQUESTS : orders
    LABORATORY_REQUESTS ||--o{ LABORATORY_RESULTS : receives
    PATIENTS ||--o{ PATIENT_CARE_RELATIONSHIPS : authorizes
    PATIENT_CARE_RELATIONSHIPS ||--o{ PATIENT_ACCESS_GRANTS : controls
    CHAT_CONVERSATIONS ||--o{ CHAT_MESSAGES : contains
```

> Note: This is a defense-oriented conceptual model, not a replacement for the complete live Supabase schema or migration history. Row Level Security policies, helper functions, triggers, indexes, and audit tables remain defined in the database layer.
