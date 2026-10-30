# HarmonyOS Health Read Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent failed Huawei Health reads from overwriting valid local values while allowing every individually authorized health domain to refresh.

**Architecture:** Introduce HealthKit-independent authorization, read-result, snapshot, and merge-policy models. `HuaweiHealthService` reports authorization and read status per domain; `Index` applies only successful domains and persists steps only after a successful step read. `SleepDetailPage` gates only on sleep authorization and handles sleep read failure explicitly.

**Tech Stack:** ArkTS, ArkUI, HarmonyOS Health Service Kit, Preferences, Hypium local unit tests, Hvigor.

## Global Constraints

- Health data remains read-only, local-only, and excluded from logs and cloud backup.
- Health read failures must not replace existing in-memory or Preferences values.
- A successful read returning zero is real data and may replace an old value.
- Steps, resting heart rate, and sleep authorization are tracked independently.
- User-visible text remains static and receives no animation.

---

### Task 1: Pure authorization and merge policy

**Files:**
- Create: `entry/src/main/ets/model/HealthSyncPolicy.ets`
- Modify: `entry/src/test/LocalUnit.test.ets`

**Interfaces:**
- Produces: `HealthAuthorizationStatus`, `HealthDomainReadStatus`, `HuaweiHealthSnapshot`, `LocalHealthState`, `HealthMergeResult`, and `HealthSyncPolicy`.

- [x] Add tests proving no authorization, partial authorization, total read failure, successful zero data, and mixed success/failure old-data protection.
- [x] Run the local unit suite and confirm it fails because `HealthSyncPolicy` does not exist.
- [x] Implement explicit per-field merge behavior and authorization helpers without platform dependencies.
- [x] Run the local unit suite and confirm all policy tests pass.

### Task 2: Per-domain Health Service contract

**Files:**
- Modify: `entry/src/main/ets/service/HuaweiHealthService.ets`

**Interfaces:**
- Consumes: policy model types from Task 1.
- Produces: `getAuthorizationStatus()`, `requestAuthorizations()` with status, and `readTodaySnapshot(status)` with per-domain `success/errorCode`.

- [x] Replace the all-or-nothing authorization query with independent flags for steps, heart rate, and sleep.
- [x] Skip unauthorized readers and return explicit unsuccessful domain statuses.
- [x] Convert caught platform errors to a sanitized numeric `errorCode`; never synthesize a successful zero result.
- [x] Build the module to type-check the platform integration.

### Task 3: Selective page updates and user state

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/ets/pages/SleepDetailPage.ets`

**Interfaces:**
- Consumes: per-domain authorization and snapshot results from Task 2.

- [x] Track three authorization flags and treat any authorized domain as connected.
- [x] Merge only successful snapshot domains; persist Preferences only when steps succeeded.
- [x] Set the sync timestamp only when at least one domain succeeded and report partial/total failures accurately.
- [x] Gate sleep details on sleep authorization alone and handle failed sleep reads without a false empty-data state.

### Task 4: Documentation and verification

**Files:**
- Modify: `README.md`
- Modify: `ARCHITECTURE.md`

- [x] Document per-domain authorization and failure-preserving data flow.
- [x] Run the complete local unit suite.
- [x] Run the unsigned debug HAP build.
- [x] Review the final diff for privacy, scope, and accidental generated files.
