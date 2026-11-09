# First implementation plan: dependable single-word control

Draft for owner review, 9 November 2026. Based on the [owner-reviewed roadmap](HANDS_FREE_ROADMAP.md), merged in [PR #1](https://github.com/GitHubbler/TSVideoPlayer/pull/1) at `69115377475d1cc41c4f83138685e174ec54de42`.

This document proposes implementation work; it does not authorize starting it. Review comments should be incorporated here before coding. No application code changes accompany this plan.

## Outcome and boundaries

Deliver a small, testable macOS player that restores a prepared lesson session, starts listening after ordinary launch, and responds predictably to single-word commands throughout the owner's 40–50-minute ride. Make loss of listening obvious and recover automatically when possible. Keep the existing vocabulary and native SwiftUI/AVPlayer/Speech stack.

The supported setup is the owner's Mac mini and Bluetooth headset, reported as Shokz OpenMove S661-ST-GY-CA-153 or similar, with its built-in microphone and headset output. The screen is approximately 24 inches at 60 cm. Record the precise macOS version and active audio devices for hardware results; “latest public macOS” is the operating preference, not a reproducible version identifier. Fan/bike noise remains to be measured. Repeated lesson listening is frequent.

Firm constraints inherited from the report:

- Preserve single-word commands. No wake/addressing phrase, mandatory confirmation dialogue, or extra spoken preamble.
- Initial end-of-command to visible applied-action acknowledgement target: **one second**, with later improvement. Separately record recognition, dispatch and observable playback-effect timing. Do not display success before applying an action.
- Aim for at least 95% first-attempt command success, no duplicates/unintended playback changes, and no required touches during normal operation on the supported setup. These are acceptance targets, not current measurements.
- Initial permission/content preparation may be manual. Later valid saved-session launches must not need a mic click. Restore paused; the rider may say “play.” Missing hardware, denied permissions and inaccessible content must be truthful pre-ride errors.
- Audio/transcript retention is permitted. Use useful bounded fixtures/logs; avoid unlimited recording or a new privacy-policy settings project. Preserve existing recognition fallback behavior unless reliability evidence justifies changing it.
- iOS, speaker output, other headset qualification, distribution/sandbox changes, queues, A–B loops and a new replay feature are deferred. Improve the current repeated “back” workflow first.

## First coding step and reviewable deliverables

Begin with **P0: establish reproducible tests and narrow code boundaries**. The first coding PR should provide an unsigned macOS build procedure, a test target in the tracked XcodeGen spec, a small normalized recognition-event/command contract, and a regression fixture showing the distinction between duplicate partials and intentional repeated commands. Preserve the app's externally visible behavior in this preparation slice; do not claim that a test seam alone fixes recognition.

Keep the gate/lifecycle fixes in the immediately following wave. A reproducible failing regression can be included as an explicitly expected known failure during preparation; new assertions become ordinary passing tests when the repair lands. Do not silently skip failures or merge a broken default test run. If extraction alone is too invasive to preserve behavior, combine it with the smallest command-gate repair and defer parallel execution until that interface is stable.

Each later slice supplies source, focused behavioral tests where useful, a short validation record and an updated status entry here. Proposed PR boundaries are P0 preparation, P1 command/lifecycle integration, P2 playback/session/feedback integration, and P3 acceptance evidence. Keep source fixes separate from optional diagnostic tooling when that helps review.

## Minimal boundaries that make concurrent coding useful

The repo currently has two Swift files; asking several agents to edit both would create more integration work than useful concurrency. A coordinator first establishes small ownership boundaries. Proposed names below are a plan, not a requirement to create every file or a generic framework.

- `VoiceCommand.swift`: the existing command vocabulary/aliases and associated action names. One source of truth replaces duplicated word lists and ten callback properties when integrated.
- `RecognitionEvent.swift`: normalized callback data sufficient for decisions, including session generation, transcript segment text/timing or another justified stable identity, final/error events, and a test clock boundary. Apple callbacks do not supply an application utterance ID; the adapter/gate must derive identity rather than invent certainty.
- `CommandGate.swift`: deterministic recognition-event to command decisions. No AVAudioEngine, view state, filesystem or wall-clock dependency in its tests.
- `VoiceCommandManager.swift` and, only if useful, `SpeechSession.swift`: actual recognition/capture ownership, permissions, retry scheduling and status. A small adapter seam allows lifecycle tests without a microphone; no dependency-injection framework.
- `PlayerModel.swift`: extracted existing player operations, observed playback state and owned observers. `SessionStore.swift` holds only the persisted session record and validation logic.
- A small `SessionStatusView.swift` or equivalent view component receives value state and renders listening/action/error feedback. The coordinator owns `VideoPlayerApp.swift`/`ContentView` wiring.

Agree shared types before workers start: command cases/aliases, status cases, what counts as an accepted action, session-generation ownership, event timing units, and which layer deduplicates callbacks. The gate is the single execution-decision point; the lifecycle layer rejects stale sessions and must not add a competing word cooldown. Scope cancellation/retry and command dispatch to the same current generation.

Avoid over-specifying the speech algorithm before fixtures exist. Partial-result revisions, multiple segments in a snapshot and successive identical words must be represented. Waiting exclusively for final transcription or extending a one-second cooldown may conflict with responsiveness/repeats; evaluate those choices against evidence and latency rather than adopting them as easy fixes.

## Work sequence and concurrency

### P0 — coordinator preparation, serial

Read the merged report and current source. Record exact build tools, reproduce the duplicate issue if possible, and make an unsigned baseline build. Extract only the contracts/files needed by the first concurrent wave; add the test target and deterministic event fixtures. Document build/test/signing steps and a compact supported-setup test procedure. Add a short root `AGENTS.md` pointer to the report, approved plan and validation commands when implementation begins, so future tasks find the decisions.

The coordinator owns `project.yml`, shared contracts and app wiring. Choose one active voice session/window rather than supporting competing capture owners. Record any behavior-changing single-window decision in the implementation PR. Leave deferred iOS branches alone unless they block the scoped Mac build; do not spend this slice achieving parity or deleting them wholesale.

**Exit:** clean generation/build/default test command works; the event seam can represent duplicate partials, two intentional “back” commands and stale-session callbacks; file ownership is clear. Merge this small preparation PR before launching isolated coding workers so they receive the same committed contracts.

### P1 — two concurrent coding workers, then serial integration

**Worker A: command gate and regression cases.** Own `CommandGate.swift`, command-gate tests and its event fixtures. Implement at-most-once acceptance for an intentional command while allowing two distinct repeated “back” utterances. Cover rewritten/duplicate partials, mixed command/non-command segments, rapid repeats, aliases and stale events. Document the identity rule and cases it cannot resolve from transcript data alone. Do not edit capture lifecycle, app views or the project spec.

**Worker B: recognition lifecycle and fake-session tests.** Own `VoiceCommandManager.swift`/`SpeechSession.swift` and lifecycle tests. Serialize transitions, bind the audio tap to its owned request, reject obsolete callbacks, handle completion/error independently of parsing and make retry/cancellation ownership explicit. Publish listening only after successful capture startup. Cover unavailable recognizer/input, startup failure, permission denial, stop during permission/retry, final result without command and late callbacks after restart. Use the shared gate contract; do not implement a second parser or change command meanings.

These tasks can run together after P0 because they own separate files/tests and consume stable contracts. The coordinator handles build-spec changes and app wiring. A worker needing a contract change stops that dependent part, reports the smallest proposed change, and continues independent cases; the coordinator resolves it once for both workers.

**Integration:** compare both implementations against the same event fixtures, bring their commits onto an integration branch, wire command dispatch once, and run the combined suite. Verify that result/error handling cannot disappear behind parser early returns and that a cancelled session cannot restart or dispatch. Keep per-command rearming only if evidence shows it is necessary; evaluate a persistent capture path before adopting repeated teardown as a permanent design. Add ordering regressions for any integration failure.

**Exit:** default tests pass, one intentional event sequence produces one action, two distinct repeats produce two, and stopped/stale sessions produce none. A short seated Mac/headset smoke test confirms actual capture and repeated “back” before further feature work. No claim of full ride acceptance yet.

### P2 — another concurrency opportunity, then serial session wiring

**Worker C: playback state and saved session.** Own `PlayerModel.swift`, `SessionStore.swift` and their tests. Observe real playback/item errors; own and scope observers. Persist accessible content, position, rate/volume and voice-enabled preference using a small versioned record. Validate missing media and old path-only preferences. Save periodically/at pause and avoid applying an old asynchronous restore/seek to a newly selected item. Handle no-item playback, boundaries, EOF and paused seeking according to explicit semantics in the PR. Use the access mechanism needed by the current unsandboxed Mac; do not add an App Store migration.

**Worker D: status/command feedback component.** Own the small status component and its preview/example states; consume agreed status/action values. Provide legible listening/recovering/attention-needed states, concise action outcomes and accessible icon labels. Feedback must survive recognition rearming instead of disappearing with an inactive mic icon. Validate the result at 60 cm on the actual screen. Do not modify player behavior, persistence or lifecycle code, and do not write tests that merely duplicate view literals.

**Coordinator:** wire prepared-session launch only when valid media/preferences and permission state are known; avoid repeated startup on view appearance. Restore paused and start listening when the saved preference permits it. Define explicit microphone/session-off behavior and one active session. Handle layout resizing in the Mac view. Small shared-view edits stay serial with the coordinator.

**Exit:** valid relaunch needs only spoken “play,” missing content/permissions never appear ready, rate/volume/position persist, and accepted actions match the visible state. C and D can run together; launch wiring depends on C and the P1 lifecycle. If the UI component is too small to justify a separate agent, the coordinator implements it while C runs. Learning concurrency does not require inventing extra work.

### P3 — repeatable recognition checks and hardware acceptance

Once the event/adapter contracts are stable, a worker may independently add a small recorded-audio replay runner and fixture manifest in diagnostic/test files. This can overlap P2. The coordinator alone owns any required app/project wiring. Begin with a few rider recordings: isolated commands, “back” twice with measured gaps, revisions/fillers, silence, and a short sequence of frequent lesson actions. Synthetic speech is supplementary; do not substitute it for the rider's pronunciation.

Run deterministic cases on every relevant edit. Run recorded-audio cases after recognition changes. Run short seated checks for permission prompts, Bluetooth route loss/reconnect, microphone availability, actual playback and resizing. Finally complete three representative 40–50-minute rides. Full rides validate sustained use; they are not the edit/test inner loop.

Record attempts, successful first attempts, duplicates, unintended actions, touches, latency and test environment. Mark which results are simulated, file recognition, paced audio replay, seated hardware or riding. Do not describe one layer as proof of another. If the one-second target is missed, identify recognition delay versus application delay; do not conceal it with premature feedback or quietly change the threshold.

**Exit:** acceptance record demonstrates the report's targets on the supported setup, or clearly lists the remaining failures for owner disposition. Do not add a phrase to fix false activations. If a requirement is unmet, report it and revise the implementation or plan with the owner. Only then consider configurable replay; queueing still requires evidence of between-lesson reaching.

## Test strategy: what can be automated without a jig?

**Deterministic event injection** is the first investment. For example, feed repeated snapshots of one “back” segment with the same session/timing evidence: expect one seek of −15 seconds. Feed two distinct segments/utterances, including a later snapshot containing both: expect exactly two seeks. Inject an old-generation callback after stop/restart: expect zero extra seeks. Use fake time for cooldown/retry cases; assert actions and state, not private function calls. This validates the application's interpretation of supplied evidence, not speech accuracy.

**Recorded-audio injection** exercises recognition without an acoustic setup. Apple's [audio-buffer recognition request](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest) accepts existing buffers. Pace them through the normal streaming adapter with declared sample format and preserve silence between utterances. Apple's [file recognition request](https://developer.apple.com/documentation/speech/sfspeechurlrecognitionrequest) is useful for supplementary recorded-file checks. Neither is a guarantee that live callback ordering will be identical. Keep scripted event tests deterministic; record recognizer/OS/availability-dependent results separately so platform-service variability is not misdiagnosed as a deterministic test regression.

**The actual Mac/headset** is required for capture/audio routing, acoustic noise, realistic latency and sustained use. A rider need not pedal for a basic Bluetooth/capture smoke check. No speaker/headset jig is needed initially. Build one only if a reproducible acoustic failure cannot be investigated with these cheaper layers. Speaker-output qualification remains out of scope.

For latency, record audio command-end time, first usable recognized command, accepted dispatch, player effect when observable, and UI acknowledgement. Deterministic tests measure the application's contribution, while real input supplies the end-to-end measurement. Report the denominator and any over-one-second cases alongside success rate; do not equate a fast average with passing every case.

## How to use the coding waves to learn concurrent agents

The first teaching exercise is **P1 with two coding workers**, after P0 is committed and reviewed. It demonstrates distinct responsibilities, independent tests, a shared interface and a real integration boundary. P2 then demonstrates concurrency between model/persistence and presentation. Do not launch workers from this planning PR.

For an isolated-worktree exercise in T3 Code, the coordinator should use `delegate_task` with worktree isolation rather than create child checkouts manually. Each child starts from the same committed preparation base; parent uncommitted changes are not part of that base. Inspect available provider/model capabilities before the first delegation, inherit the current settings unless the owner requests others, and keep both tasks scoped to coding rather than another broad review. The runtime returns task/thread links so the owner can inspect progress and output. No new top-level threads are needed for this exercise.

An ordinary same-provider subtask that finishes within the current turn can instead use native Codex subagents in the shared checkout. In that mode file ownership is essential because edits are immediately shared. Use one mode per wave deliberately; isolated worktrees are the proposed P1 exercise because they make each change and integration step easier to inspect.

Example worker briefs, to refine against the P0 contract:

> Worker A: Implement the approved command-gate behavior against the committed event contract. Own only the gate, its tests and fixtures. Preserve single-word aliases and the one-second target. Demonstrate duplicate partials, two intentional repeated “back” commands and stale-session rejection. Do not edit shared contracts, project.yml, capture or UI. Report changes, test evidence, open issues and commit SHA; do not spawn children or merge to main.

> Worker B: Implement the approved recognition-session lifecycle against the same committed contract. Own only capture/lifecycle files and their fake-session tests. Handle startup failure, completion/error, stale callbacks, permission/retry cancellation and truthful status. Leave command interpretation to the gate. Report changes, test evidence, open issues and commit SHA; do not spawn children or merge to main.

The coordinator owns integration and the PR to main. Worker commits remain on their isolated branches until inspected and integrated; do not ask both workers to publish competing edits to the same PR. If child PRs are requested later, link each separately and keep integration order explicit. Regenerate the ignored Xcode project from the coordinator's merged `project.yml`; never merge generated project files.

Follow completion notifications for running T3 delegates rather than polling. If an interface decision blocks a worker, resolve it explicitly; do not create a replacement worker that duplicates active work. Cancel a run that is replaced or no longer needed. After both results arrive, inspect diffs, integrate and test the combination, then open one focused implementation PR for owner review. Independent worker success does not establish integration success.

At that review, compare worker boundaries, conflicts avoided/encountered, evidence supplied, elapsed overlap and coordinator effort. Two workers may reduce independent coding time, but testing the same Mac/headset and final integration remain serial; do not promise a twofold speedup. Keep subsequent waves concurrent only where they continue to help.

## Evidence, status and owner decisions

Current status: report merged; this implementation plan is a draft. P0–P3 have not started. The only build evidence so far is the unchanged unsigned macOS baseline recorded in the report. No new tests, hardware checks or coding-agent runs have occurred for this plan.

For each coding PR, record base/head commits, owned files, command used for generation/build/tests, outcome, manual setup/version, remaining failures and whether acceptance thresholds were met. Update the relevant phase status here so future work does not mistake proposals for completed behavior.

Owner comments can confirm or alter the proposed PR boundaries, phase order, launch/EOF semantics and concurrency exercise. Single-word control, current platform/audio scope and one-second initial target are already confirmed requirements. The exact event identity rule and recognition restart strategy remain implementation questions to resolve with fixtures; they are not reasons to broaden scope.
