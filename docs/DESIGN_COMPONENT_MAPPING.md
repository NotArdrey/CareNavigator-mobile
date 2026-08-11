# CareNavigator PH Component Mapping

CareNavigator PH uses shadcn/ui only as a secondary interaction and composition reference. The application does not install or embed React, Tailwind CSS, Radix UI, npm packages, or shadcn source files. All runtime components are Flutter-native and follow the clinical design requirements and accessibility rules.

## Pattern mapping

| Reference pattern | Flutter-native CareNavigator implementation |
| --- | --- |
| Button variants | `FilledButton`, `OutlinedButton`, `TextButton`, and `AsyncActionButton` with consistent loading, disabled, destructive, icon, and live-region semantics |
| Input and form composition | Central `InputDecorationTheme`, Flutter `Form`, field-level validators, autofill hints, password visibility controls, and accessible error text |
| Card | `ContentPanel`, using thin borders and controlled radius rather than nested or shadow-heavy cards |
| Badge | `StatusTag` and preview status tokens with semantic colors, text/icon cues, and one concise screen-reader label |
| Alert and dialog | Root-navigator `AlertDialog` helpers with blocking scrims, explicit cancel/confirm actions, destructive variants, and focus-safe routing |
| Sheet and drawer | Root-navigator modal sheets with safe areas, drag handles, keyboard accommodation, and viewport constraints |
| Toast/notification | Root `ScaffoldMessenger` feedback with one visible message at a time |
| Table/data rows | Responsive operational rows that retain labels on narrow screens and structured columns at desktop widths |
| Navigation menu | Flutter GoRouter public header, mobile bottom navigation, and one desktop workspace sidebar |
| Command/search palette | Root-modal Flutter workspace finder with role-scoped results, touch selection, Ctrl/Command+K activation, Enter navigation, clear/empty states, safe-area constraints, and keyboard-inset handling |
| Skeleton/empty/error states | Shared contract-gate and live-region data-state components with heading semantics and recovery actions |
| Switch and preference rows | `SwitchListTile` with confirmation, disabled/busy behavior, and text that communicates state without relying on color |
| Calendar/date picker | Root Material date and time pickers, preserving safe overlay order and keyboard/focus behavior |

## CareNavigator-specific overrides

- Deep navy-teal remains the primary clinical-navigation color.
- Red is reserved for emergencies, destructive actions, and critical failures.
- Operational density and flat sections take precedence over generic dashboard card grids.
- Patient, doctor, hospital-administrator, and super-administrator workspaces use different information structures.
- Every action remains connected to a typed controller/repository boundary; visual composition never substitutes for handler verification.
- Live healthcare records, metrics, and identifiers are never copied from component examples.

## Dependency rule

Adding shadcn/ui itself is not technically compatible with the required Flutter runtime. If a future Flutter package reproduces a useful interaction, it may be considered only when it supports the active Flutter version, mobile and web, accessibility, the centralized CareNavigator theme, Riverpod, GoRouter, and repository boundaries without creating a second design system.
