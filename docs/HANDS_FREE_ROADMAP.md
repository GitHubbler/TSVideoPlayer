# A dependable hands-free lesson player

Planning report, 8 November 2026; revised 9 November 2026 after owner review on [PR #1](https://github.com/GitHubbler/TSVideoPlayer/pull/1). Reviewed source baseline: `8d81ee16e39035f8dae49da2da43268d53327db3`.

## Recommendation

Keep the native player small and make the complete ride dependable before expanding its feature set. Start with one supported device and audio setup, repair recognition ownership and truthful status, then deliver remembered-session launch and clear command feedback. Add a configurable short replay only after real rides demonstrate reliable control. Queueing should follow demonstrated demand. iOS and speaker output are outside the current scope. Retain single-word commands; an addressing phrase is explicitly excluded.

This combines the reliability-first proposal (A), the most useful session improvements from the learning-first proposal (B), and the inexpensive reproducibility/testability work from the portability-first proposal (C). It is the preferred plan under the confirmed scope below, rather than a universally optimal feature list. A wholesale rewrite, a generic media architecture, and a custom speech engine are disproportionate to this project.

The app is already useful: native playback, explicit play/pause, rewind/skip, rate and volume adjustment cover much of a language-lesson workout. The main gap is confidence that these controls remain available and behave deliberately throughout a ride.

## Scope, assumptions, and review method

Three agents independently reviewed crucial aspects, then received a second task proposing a path under a different value preference:

- **Interaction reviewer:** hands-free workflow, feedback, discoverability, accessibility and lesson practice; subsequently proposed B, optimizing uninterrupted learning.
- **Reliability reviewer:** recognition/capture lifecycle, callback ordering, playback and recovery; subsequently proposed A, optimizing predictability and maintenance cost.
- **Maintainability reviewer:** build/configuration, platform completeness, privacy, architecture and testing; subsequently proposed C, optimizing portability and reuse.

The primary reviewer read both Swift files, the issue, tracked build configuration, entitlements and recent history; checked the reviewers' evidence; performed the clean-generation/build check below; and selected the combined plan. All reviews were read-only. This change adds only this report.

The owner confirmed the recommended approach, personal-tool scope, local videos and English commands. iOS is not used. The supported riding setup is a Mac mini, normally kept on the latest public macOS, with a Bluetooth headset for both output and its built-in microphone: Shokz OpenMove, reported model S661-ST-GY-CA-153 or similar. Record the exact macOS version and active input/output route for each hardware test rather than assuming “latest” is reproducible. The approximately 24-inch display is about 60 cm away; rides last 40–50 minutes. Repeated listening is frequent and tapers off as lessons become familiar. Fan/bike noise remains to be measured.

The owner reports that switching to headset output addressed lesson-audio interference. Validate the current headset setup; speaker output and other audio setups need no acceptance coverage in this iteration. This is firsthand operating evidence, not a laboratory guarantee of zero false triggers. Do not infer the microphone's sensing technology from the headset's bone-conduction output.

Single-word control is a firm requirement. An addressing/wake phrase is a non-starter even if it could improve recognition; the owner prefers imperfect single-word commands. Retaining audio and transcripts for useful diagnosis/testing is acceptable: privacy is not a project constraint. Keep collection bounded and purposeful for performance, storage and reproducibility, rather than imposing local-only recognition or a privacy-driven retention prohibition.
Interpret “except for launch” literally for **normal use after initial setup**: permissions and content selection may require an initial preparation step, but an ordinary later launch must restore a ready session without a microphone-button click. Starting playback may remain a spoken action. Revoked permissions, a physically disconnected microphone, or a deleted lesson cannot always be repaired by voice; expose these conditions before riding rather than promise impossible recovery.

The owner also confirmed the launch-only interpretation above. Before implementation, measure the remaining fan/bike noise conditions and record a versioned test environment. The owner requires an initial command acknowledgement target of **one second**, with further improvement later; two seconds is too long. Measure from the end of the spoken command to visible applied-action feedback, and record dispatch/player-effect timing separately so a fast message cannot hide a slow action.
## What the source establishes

Line references below refer to the reviewed baseline. They establish implementation facts and plausible failure mechanisms, not measured incidence on the rider's hardware.

| Priority | Finding and source | Consequence / response |
| --- | --- | --- |
| First | Partial-result last words directly match common commands without an addressing gate: `VideoPlayer/VoiceCommandManager.swift:114–161,175–201`. | The owner reports lesson-audio interference was resolved by headset output. Retain single-word commands and validate that setup; defer speaker support. Improve duplicate/result handling without an addressing phrase. |
| First | Rearming cancels and replaces shared recognition state after each accepted command; callbacks carry no session identity: `VoiceCommandManager.swift:124–218,240–253,268–277`. Error suppression uses a one-second time window. `VideoPlayer/ISSUES.md:3` records duplicate execution. | Stale callbacks can affect a newer session or schedule recovery. This is a plausible contributor, not a proven duplicate root cause. Establish session ownership and reproduce the issue before declaring it fixed. |
| First | Early returns during result parsing can bypass error handling; final completion has no explicit handling: `VoiceCommandManager.swift:128,161–165,204–217`. Engine startup errors are swallowed before `isListening = true`: `220–224`. | Capture/recognition can fail while status is misleading. Handle terminal events independently of command decisions and derive status from successful startup/recovery. |
| First | The mic button is the listening entry point; appearance restores media paused without enabling voice: `VideoPlayer/VideoPlayerApp.swift:185–187,212–235`. | Normal launch is not yet a launch-only hands-free workflow. Restore a deliberate saved voice-session preference and visibly start listening after setup. |
| First | `showSettingsAlert` is written but never presented; unavailable recognition/no input receive no useful UI: `VoiceCommandManager.swift:10,47–57,76–88,105–108`; `VideoPlayerApp.swift:179–228`. | Denial, unavailability and intentional off look similar. Add distinct actionable states. On macOS, explicitly validate microphone authorization as well as speech authorization; the current macOS path only requests the latter (`61–69`). |
| Next | Audio tap reads a mutable manager request, while callback work changes manager state outside explicit main-actor hops: `VoiceCommandManager.swift:110–112,124–218`. | Audit callback execution boundaries; bind captured audio to its owned request and serialize lifecycle/command decisions. A successful build does not establish runtime race freedom. |
| Next | `play()` declares success immediately; media-end observation is global and its token is not retained: `VideoPlayerApp.swift:61–78`. | UI reflects requested rather than observed playback. Observe item/time-control/error state; scope and remove the observer. Use one active voice session/window initially. |
| Next | Persistence saves a path only, not position or settings; restoration does not validate readability: `VideoPlayerApp.swift:85–109`. | Missing/moved content can appear restored without usable playback. Save a small session record, validate it, and report failure. Use durable access appropriate to the supported distribution; bookmarks are not automatically required for the current unsandboxed Mac. |
| Next | Feedback is raw recognized text, briefly visible only while listening; status chips use caption-sized text: `VoiceCommandManager.swift:136–170,256–265`; `VideoPlayerApp.swift:189–201,238–248`. | “Heard” and “executed” are hard to distinguish at bike distance. Show the accepted action/outcome and persistent session status; add explicit accessibility labels to icon controls. |
| Next | Player layers are sized only at creation and update hooks are empty: `VideoPlayerApp.swift:258–281`. | Mac window resizing needs runtime verification and a layout hook if reproduced. Define behavior at EOF and seek boundaries as well (`71–74,111–135`). |
| Conditional | iOS is configured in `project.yml:5–6,20`, but its picker state is unused and only macOS exposes file opening: `VideoPlayerApp.swift:163–177,225–227`. Playback and voice also independently select conflicting iOS audio categories (`VideoPlayerApp.swift:89–91`; `VoiceCommandManager.swift:92–98`). | A fresh iOS install has no visible content-import workflow. Do not equate a configured target with a usable product. Record this limitation and defer iOS implementation/testing; iOS is not used by the rider. |
| Policy | On-device recognition is required only when supported: `VoiceCommandManager.swift:118–120`. Sandbox is disabled: `VideoPlayer/VideoPlayer.entitlements:5–6`. | Current recognition can permit network fallback; entirely offline operation is not guaranteed. There is no owner requirement to prevent this. Preserve existing behavior unless reliability testing justifies a change; do not add an offline-policy UI solely for privacy. Broad distribution/sandboxing remains separate work. |

The tracked project has no test target, README or CI. `project.yml` is the build source of truth; generated Xcode projects are ignored. The code's small size is an asset: retain SwiftUI, AVPlayer and Speech, and extract only boundaries that help control real failure modes.

## Three proposed paths

### A — reliability and low maintenance first

The original reliability proposal ranks predictable hands-free control above simplicity/privacy, convenience and platform breadth. Owner review removes privacy as a limiting value; retain the reliability and simplicity priorities. Support one real setup, measure the existing failures, give recognition a single owner with explicit states, reject stale callbacks, and introduce focused tests. Then make command intent/feedback clear and verify sustained rides. Add features only when they prevent an observed touch.

**Advantages:** shortest route to trusting the current tool; small support surface; inexpensive evidence on actual hardware. **Costs:** fewer lesson conveniences and limited portability; disciplined acceptance work can feel slower than adding buttons. Pure A risks declaring isolated command reliability sufficient while session launch/resume still requires reaching. The combined plan therefore makes remembered launch part of the minimum outcome.

### B — uninterrupted learning and convenience first

The interaction reviewer prioritizes useful lesson practice and fewer interruptions, accepting modest additional state and maintenance. Build a ready-to-ride saved session, clear action feedback, and measured intent handling. Add a fixed/configurable short replay before considering A–B loops; add a prepared lesson queue only if between-lesson reaching is observed.

**Advantages:** directly improves why the rider uses the app; position restore and replay save lesson context. **Costs:** more persistence, command semantics and edge cases before the recognition foundation is proven. A queue does not help a rider who mainly watches one long lesson; A–B marking adds spoken interaction and loop-state complexity. Borrow saved-session launch and feedback immediately, defer extra replay/queue semantics until reliability passes. Existing “back” already provides a basic 15-second replay mechanism.

### C — portability and future reuse first

The maintainability reviewer prioritizes reproducible onboarding, usable macOS/iOS workflows and a small shared command/session core. Establish clean builds for both destinations, add deterministic tests, finish iOS import/access/audio behavior, and run device acceptance before shared session features.

**Advantages:** easier handoff to another developer/user, broader device choice and clearer platform boundaries. **Costs:** substantially more device, permission and file-access testing, with continuing two-platform maintenance. This can consume most effort without reducing today's rider's interruptions. Borrow build documentation and a small test seam now; defer parity until a second device/user has a concrete need. Even C excludes a plugin framework, cloud accounts and a custom recognizer.

## Selection and value tradeoffs

The selection uses this preference order: (1) responsive single-word control through a normal ride without reaching, duplicate actions or unintended playback changes, (2) keep fixes understandable for one maintainer, (3) preserve lesson context and reduce repeated effort, (4) broaden device support only on demonstrated demand. Privacy does not constrain this project. The zero-false-action target remains useful for the supported headset, but failure to meet it does not authorize adding an addressing phrase. Reliability is a gate, so a speculative queue feature cannot compensate for silent microphone failure.

Under these preferences, **A plus essential B and inexpensive C work** is preferable to any full proposal alone. Compared with pure A, it spends more on persistence and usability but satisfies the actual launch-to-ride goal. Compared with full B, it postpones attractive learning controls until they can be trusted. Compared with C, it sacrifices near-term platform choice to keep validation affordable. There is no evidence supporting numerical utility scores; the ordering and assumptions are explicit so the owner can change the decision.

The owner has confirmed the combined approach and Mac/headset-only scope. If that setup already passes the reliability gates, accelerate B's replay experiment because frequent repeated listening is now confirmed. If single-word recognition remains imperfect, investigate recorded failures and adjust implementation without adding a prefix or silently relaxing the one-second goal. Wider platform and speaker support can be reconsidered only if needs change.
## Feasible implementation sequence

Each slice should be independently reviewable. Scope is expressed as small changes and exit gates, not calendar promises; runtime investigation is the main uncertainty.

1. **Baseline and supported setup.** Document generation/build/signing and command meanings; record the confirmed Mac/headset setup, remaining noise conditions and baseline duplicate/miss/false-trigger cases. Define initial setup versus ordinary launch. Use one active voice session on macOS. Exit: a clean checkout builds and another person can reproduce the test procedure. Record event times, session IDs and actions/errors; retain short audio/transcript fixtures when useful. The owner permits retention. Bound recordings/logs to control storage and overhead, and measure diagnostic overhead when timing commands.

2. **Own recognition and recovery.** Introduce one lifecycle owner and states such as off, starting, listening, recovering and attention-needed. Tag each session and reject obsolete callbacks. Serialize transitions, capture each request deliberately, process completion/errors independently of parsing, and own/cancel retries with bounded backoff. Publish listening only after startup succeeds. Test stopping during permission requests/retries, start failure, final/empty/non-command results, result-plus-error, and stale callbacks. Coordinate capture/playback configuration on the first platform. Exit: scripted lifecycle failures cannot cause duplicate action dispatch or resurrect intentionally stopped listening.

3. **Make intent and outcomes trustworthy.** Use one command enum/catalog and a small deterministic interpretation/execution gate with controllable time/session identity. Distinguish repeated partial updates from a new intentional repeated command; a longer cooldown alone does not solve this. Keep the existing single-word vocabulary; no addressing phrase. Use scripted transcript events and recorded speech to investigate duplicates, partial revisions and rapid intentional repeats. Show a large accepted-action message and persistent truthful state; keep feedback silent initially to avoid competing with lessons. Add a concise command reference and accessible labels. Observe real player/item state, own observers, verify resize, and define EOF/boundary behavior. Exit: core command and playback acceptance cases pass on the supported setup.

4. **Deliver normal launch without reaching.** Remember accessible content, position, selected rate/volume and a deliberate voice-enabled preference. On ordinary launch validate content, restore paused at the intended position and enable listening with an obvious active-mic indicator. First-run permission/setup and unusable content get explicit pre-ride guidance. Save position periodically/at pause as appropriate; do not rely solely on app termination. Define a clear way to end listening/session, with no promise of voice reactivation after capture is off. Retain the current preference for on-device recognition when available, with existing fallback behavior; add no local-only restriction unless evidence requires it. Exit: valid saved-session launch needs only a spoken play command; denial/missing content never masquerades as ready.

5. **Prove the whole ride, then add one earned feature.** Run the acceptance protocol below. If existing rewind is awkward, trial a configurable short replay using existing seeking and clear state-preserving semantics. Keep it only if it helps practice. Add a small prepared queue with explicit next-lesson/EOF behavior only when rides show a need. A–B loops, voice file browsing, automatic sentence boundaries, subtitle intelligence, streaming integration, cloud sync, exercise telemetry and broad distribution remain outside this plan.

## Acceptance protocol and stopping rule

These are proposed targets, not measured current performance or universal guarantees. Baseline measurements may justify changing them before implementation.

- Focused automated scenarios: duplicate/rewritten partials cause at most one action per intentional utterance; two distinct repeated “back” utterances cause two actions; stale callbacks cause none. Test final/error combinations, pending permission/retry cancellation and startup failure. Add only playback/persistence boundary tests that protect actual behavior.
- Bench checks on the supported device: fresh permission grant/denial, saved launch, moved/deleted lesson, EOF, paused seeking, rate/volume bounds, resize and available microphone route/interruption cases. Clear irrecoverable states may require pre-ride intervention; recoverable recognition interruption must retry visibly without a mic click.
- Three representative 40–50-minute rides, using actual lesson content, distance, bike/fan noise and audio route: zero required touches under normal conditions, zero duplicate actions, and zero unintended playback-changing actions. Use the actual headset with lesson playback and record exposure duration and command count. Speaker-output and other-setup interference tests are deferred.
- Target at least 95% first-attempt success in a recorded sample of intentional core commands and visible applied-action acknowledgement within one second of the end of the spoken command, with further latency reduction as a later goal. Log successful/attempted commands and latency; do not infer quality from a handful of successful demos. Include deliberate rapid repeats, long silence and pause/resume cycles.
- At bike distance, the rider can distinguish listening, recovery, accepted action and attention-needed. Verify saved position and settings through relaunch. Keep a short issue entry for every failure with reproduction conditions and useful audio/transcript fixtures where available; retention is permitted by the owner.

### Test automation without a rider on every iteration

The owner's question about synthetic injection has a qualified **yes**: inject normalized transcript events and a controllable clock/session ID into the command gate to test two distinct “back” utterances, duplicate partials, revision ordering and late callbacks deterministically. Inject failures into a small recognition-session adapter to test restart/stop races. These tests validate application decisions; they cannot establish that real speech is transcribed correctly or that the microphone route works.

For the next layer, replay short recorded rider commands and pauses through Speech using existing audio buffers. Apple's [audio-buffer request](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest) supports existing buffers; a [file recognition request](https://developer.apple.com/documentation/speech/sfspeechurlrecognitionrequest) supports recorded files. Paced buffer replay through the application's normal streaming adapter is the closer lifecycle test. File recognition is a useful supplementary accuracy check, not proof of live callback timing or end-to-end latency. Synthetic speech can broaden cases, but use actual rider recordings as the representative fixtures.

No speaker/headset jig is needed for deterministic logic tests or direct recorded-audio injection. Those layers bypass Bluetooth, microphone acoustics and capture-device handling. Add short, seated checks on the real Mac/headset for those boundaries, then use the full rides as final acceptance rather than the inner development loop. A physical acoustic jig is optional only if later failures specifically require it; it is not the first deliverable.

### Owner feedback incorporated

All ten inline comments on PR #1 were incorporated: approach confirmation ([line 7](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514129479)); scope/iOS clarification ([line 23](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514134434)); launch interpretation ([line 25](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514135346)); riding setup ([line 27](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514136136)); headset resolves interference ([line 35](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514136825)); retention permitted ([line 82](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514138593)); no addressing phrase ([line 86](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514139267)); synthetic-test question ([line 96](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514139915)); defer other audio setups ([line 98](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514140422)); one-second target ([line 99](https://github.com/GitHubbler/TSVideoPlayer/pull/1#discussion_r4514140928)). These links preserve provenance; the operative facts and decisions are in this document so later work need not retrieve the PR discussion.

Stop expanding scope when launch, ordinary control, recovery and three rides pass. Continue using the app and prioritize the next actual interruption. Passing these checks provides confidence for the tested setup, not proof across microphones, accents or platforms.

## Verification performed for this report

The parent reviewer generated a fresh ignored project in a separate report worktree using **XcodeGen 2.45.4**, then built the unchanged baseline with **Xcode 26.5 (17F42)**:

```sh
xcodegen generate
xcodebuild -project VideoPlayer.xcodeproj -scheme VideoPlayer \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/VideoPlayer-planning-build \
  CODE_SIGNING_ALLOWED=NO build
```

Result: **BUILD SUCCEEDED**. The log included an App Intents metadata extraction warning because the app does not depend on AppIntents. This demonstrates unsigned macOS build reproducibility on this machine, not signing/distribution readiness. The generated project and build products are not part of the PR.

No app launch, microphone/permission exercise, iOS build/device test, network trace, accessibility inspection or mounted-bike session was performed. The duplicate issue and prior crash-fix history remain inputs to investigation, not verified regressions or verified fixes. The owner approved the direction and requested these revisions and merge. This remains a documentation-only change; implementation will follow a separately reviewed plan.
