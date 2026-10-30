# HarmonyOS Log Redaction and Static Text State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure HarmonyOS runtime logs never serialize framework or business objects and tab text state changes without animation.

**Architecture:** Add a source-policy verification script that scans only maintained ArkTS sources, then replace scaffold logging with fixed operation/error-code/duration fields and remove the animation transaction around tab selection. Keep local Preferences serialization unchanged because it is persistence, not logging.

**Tech Stack:** ArkTS, ArkUI, HiLog, Node.js source-policy check, hvigor.

## Global Constraints

- Changes remain inside `bio-balance-Harmony/`.
- Logs contain only fixed operation names, stable technical tags, error codes, and durations.
- Health raw values and serialized framework/business objects never enter logs.
- Text properties are not animated; tab text state changes synchronously.
- No network upload or new health-data collection is introduced.

---

### Task 1: Source-policy regression gate

**Files:**
- Create: `bio-balance-Harmony/tools/verify-source-policy.mjs`
- Create: `bio-balance-Harmony/tools/source-policy.test.mjs`
- Modify: `bio-balance-Harmony/entry/hvigorfile.ts`

**Interfaces:**
- Consumes: maintained `entry/src/main/ets/**/*.ets` source files.
- Produces: exit code `0` when no serialized log payload or animated text-bound state update is found; exit code `1` with file/line diagnostics otherwise.

- [x] **Step 1: Write the failing policy check**

  Implement a Node.js script that recursively scans maintained ArkTS source, rejects `hilog`/`console` statements containing `JSON.stringify`, and rejects `animateTo` blocks that mutate `selectedTab`.

- [x] **Step 2: Run the check to verify RED**

  Run: `/Applications/DevEco-Studio.app/Contents/tools/node/bin/node tools/verify-source-policy.mjs`

  Expected: FAIL identifying both Ability object serialization and `Index.ets` tab animation.

### Task 2: Minimal production fixes

**Files:**
- Modify: `bio-balance-Harmony/entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `bio-balance-Harmony/entry/src/main/ets/entrybackupability/EntryBackupAbility.ets`
- Modify: `bio-balance-Harmony/entry/src/main/ets/pages/Index.ets`

**Interfaces:**
- Consumes: `BusinessError.code`, `Date.now()`, and synchronous `selectedTab` assignment.
- Produces: redacted HiLog fields and instantaneous tab text-state changes.

- [x] **Step 1: Replace serialized load callback logs**

  Capture `startedAt`, log fixed `operation=load_content`, public numeric `errorCode`, and `durationMs`; do not interpolate `err` or callback `data`.

- [x] **Step 2: Replace serialized backup logs**

  Log fixed `operation=backup` and `operation=restore` only; do not serialize `BundleVersion`.

- [x] **Step 3: Remove the tab animation transaction**

  Assign `this.selectedTab = index` directly inside `.onClick` so dependent Text color and weight update synchronously.

- [x] **Step 4: Run the policy check to verify GREEN**

  Run: `/Applications/DevEco-Studio.app/Contents/tools/node/bin/node tools/verify-source-policy.mjs`

  Expected: PASS.

### Task 3: Build and final scans

**Files:**
- Verify only; no additional production files.

**Interfaces:**
- Consumes: the modified HarmonyOS module.
- Produces: unsigned debug HAP and evidence that source-policy violations are absent.

- [x] **Step 1: Build the HarmonyOS entry module**

  Run the repository-documented hvigor `assembleHap --no-daemon` command with `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk`.

- [x] **Step 2: Re-run focused global scans**

  Confirm maintained ArkTS source has no logged `JSON.stringify`, no `console` calls, and no `animateTo` transaction affecting text-bound state.

- [x] **Step 3: Review the scoped diff**

  Confirm no network API, health-data query, or file outside `bio-balance-Harmony/` was added or modified by this task.

## Verification Result

- Source-policy tests: 12 passed, 0 failed, including dynamic domain/tag and logger-alias bypass cases.
- Build-gate mutation check: a temporary `console.info` violation stopped `assembleHap` before compilation; the fixture was then removed.
- Unsigned debug HAP: `BUILD SUCCESSFUL`; only pre-existing warnings and the expected missing-signing-profile warning remain.
