# Claude Code plan view

**Status:** In progress
**Created:** 2026-11-07
**Last updated:** 2026-11-07

## Resume from here

Phase 1 is done: `ParchmentCore` has `TextChange` and `PlanSteps`; the new `ParchmentAgent` target has hook
event parsing, sessions, todos, progress, the plan file rule, the inbox and the settings installer. 96 package
tests pass on Linux (`/opt/swift/usr/bin/swift test --package-path Packages/ParchmentCore`; the toolchain was
downloaded from swift.org into `/opt/swift`). The hook script was also run in a fake home folder: it stays quiet
when Parchment is not running, saves plan events and calls `open -g`, and leaves no temp files.
Next: Phase 2 (reload on change, read-only). The sandbox has no macOS, so app code is only checked by the
GitHub Actions "Build" run.

## Context

Parchment is a native Markdown editor for the Mac (see `README.md` and `docs/plans/2026-11-06-parchment-mac-app.md`).
The user runs Claude Code in a terminal on the same Mac and wants Parchment to show the plan Claude is working
on, live: what the agent is doing right now and how far through the plan it is, with effects that make it feel
like an AI is writing in the document.

Plans come in any shape: Claude Code plan-mode files (`~/.claude/plans/*.md`, or `plansDirectory`), plan-writer
files like this one, or hand-written notes. There may be no checkboxes and no "Resume from here" section, so
Parchment cannot rely on any section name.

Claude Code tells Parchment what it is doing through hooks: small shell commands Claude Code runs on events
(before and after each tool call, when it stops, when it needs permission, when helpers start and stop).
Each hook receives one JSON object on stdin with `session_id`, `cwd`, `hook_event_name`, and per event fields
(`tool_name`, `tool_input`, `tool_response`, `agent_id`, `agent_type`, `notification_type`, ...).
`ExitPlanMode`'s `PostToolUse` carries `tool_response.filePath` and `tool_response.plan`.

## Goals

- Connecting is one menu item: **Parchment > Connect to Claude Code…** shows exactly what it adds to
  `~/.claude/settings.json`, adds it on confirm, and **Disconnect** removes only Parchment's entries.
- When Claude starts writing a plan-like Markdown file, Parchment opens it **in the background** (does not
  steal focus), launching itself if needed.
- **One window per Claude session.** A new plan in the same session replaces that session's window.
- Plan windows are **read-only** while the session is active. They become editable when the session ends or
  the user picks **Stop Following**.
- The window reloads as Claude edits the file, applying only the changed range.
- Progress works for any plan: checkboxes if present, else Claude's todo list, else the plan's structure.
- Effects (all off or static when Reduce Motion is on):
  - **Wet ink:** text Claude just wrote starts faint and darkens over about 0.6s.
  - **Live checkboxes:** the current step's circle pulses; a box Claude ticks fills in with an animation.
  - **Shimmering status pill:** "Claude · Editing EditorView.swift · 6 of 9" with a light sweep while working;
    still while waiting ("Waiting for you"), done ("Done") or stale ("Last update 6 min ago").
  - **Plan progress line:** the top line shows plan progress (instead of scroll position) with a moving glint
    while working.
  - **Claude's caret:** a vermilion bar with a small name tag at the end of Claude's last change.
  - **Follow Claude:** scrolls to each change unless the user scrolled in the last 4 seconds. Toggle in View menu.
  - **Margin marks:** a thin vermilion bar beside lines just changed, fading after about 4s.
  - **Activity ticker:** the last 3 actions ("Edited StatusPill.swift ✓", "Ran swift test ✗") above the pill,
    each fading out after about 8s.
  - **Helpers:** steps a subagent is working on get a small tag with the helper's name (e.g. "Explore");
    the pill says "Claude + 2 helpers".

## Non-goals

- No skill. Plans are not reformatted for Parchment.
- No macOS notifications, Dock badge, Dock progress or sounds. The pill is the only status signal.
- No support for cloud sessions, the desktop app or IDE extensions (they may work if they run hooks locally,
  but are not tested).
- No editing while Claude works and no merging of simultaneous edits.
- No `Ctrl+G` external-editor integration (it would need a `parchment --wait` command-line tool).
- No outline popover changes.
- No reading of Claude Code's transcript files (undocumented format). Only documented hook input is used.

## Decisions made

- **Data channel: hooks writing one file per event into an inbox folder.** Chose this over appending to one
  JSONL file (large `Write` payloads from several sessions could interleave), over a local socket or URL scheme
  (needs Parchment running and a client in the hook), and over reading transcripts (undocumented). The hook is a
  tiny `/bin/sh` script: `cat` stdin to a temp file, `mv` it into `~/Library/Application Support/Parchment/Inbox/`.
  `mv` is atomic, so Parchment never reads half a file. No `jq` or other dependency.
- **Launching Parchment from the hook:** only when Parchment is not running (`pgrep -xq Parchment`) and the event
  is plan-related (`ExitPlanMode`, or a `file_path` ending in `.md` that is plan-like). Otherwise, if Parchment
  is not running, the hook writes nothing, so the inbox cannot grow while the app is closed. Chose this over
  always launching (would open Parchment for every Claude session) and over never launching (the user would
  have to remember to open it first).
- **Plan-like file rule:** a `.md`/`.markdown` file that is the `ExitPlanMode` file, or is inside
  `~/.claude/plans/`, or has a path component named `plans` (any case), or whose file name contains `plan`
  (any case). Also any Markdown file the user already has open in Parchment that a session edits. Chose a
  path rule over content sniffing because plans have no reliable content marker.
- **Progress sources, in order:** (1) checkboxes in the file, shown as "6 of 9"; (2) Claude's todo list
  (`TodoWrite`, or `TaskCreate`/`TaskUpdate`), shown as "6 of 9"; (3) plan structure (numbered list items, else
  headings), shown as "Step 3 of 7" because done-ness is a guess. Chose layering over a single source so every
  plan gets something.
- **Current step:** in-progress todos matched to steps by word overlap; else the first unchecked task; else the
  step containing Claude's last edit. Several steps can be current at once (helpers).
- **Logic placement:** text diffing and plan step extraction go in `ParchmentCore` (stays Foundation-free).
  Hook event parsing, session state, todo matching, progress, the plan-like rule, inbox reading and settings
  merging go in a new `ParchmentAgent` target in the same package (imports Foundation, builds on Linux). Both
  are unit tested. Chose a new target over adding Foundation to `ParchmentCore` to keep the core's rule.
- **Reload strategy:** a per-window file watcher (`DispatchSource` vnode on the file; on delete or rename,
  re-open after a short delay, since editors and Claude may replace the file). On change, read the file and
  replace only the changed range in the text storage, with undo registration disabled, so the document is not
  marked dirty. If SwiftUI swaps in a new document instance for the same URL (NSDocument auto-revert), the
  coordinator applies the same diff instead of `loadText`. Applies to any window with no unsaved changes;
  effects only run when a Claude session is attached.
- **Read-only:** `textView.isEditable = false` while a session is attached and not ended. When it becomes
  editable again, Parchment asks the NSDocument to revert to the file, so its stored modification date is
  current and a later save does not warn about an outside change.
- **Opening windows:** `NSDocumentController.shared.openDocument(withContentsOf:display:)`, without activating
  the app. A session's previous plan window is closed only if Parchment opened it automatically.
- **Animation driver:** `NSView.displayLink(target:selector:)` on the text view, running only while an effect is
  live; invalidates only affected rects. Effects are drawn in `ParchmentTextView.draw(_:)` (overlays) and in
  `MarkdownLayoutManager` (task circles). Chose drawing over temporary text attributes because attributes cannot
  fade smoothly between the styler's many colors.
- **Installer target:** user-level `~/.claude/settings.json`, so it works in every project. Parchment's entries
  are recognised by their command containing `Parchment/claude-hook.sh`; everything else in the file is kept
  as is, and a backup `settings.json.parchment-backup` is written first.

## Files touched

Package (`Packages/ParchmentCore/`):

- `Package.swift` (modify) - add `ParchmentAgent` library target and `ParchmentAgentTests`.
- `Sources/ParchmentCore/TextChange.swift` (create) - smallest changed range between two `MarkdownText`s.
- `Sources/ParchmentCore/PlanStep.swift` (create) - `PlanStep` and `PlanSteps.steps(in:text:)`.
- `Sources/ParchmentAgent/AgentEvent.swift` (create) - decode one hook JSON object into a typed event.
- `Sources/ParchmentAgent/AgentSession.swift` (create) - per-session state and `apply(_ event:)`.
- `Sources/ParchmentAgent/AgentTodo.swift` (create) - todo item model, `TodoWrite` and `TaskCreate`/`TaskUpdate` handling.
- `Sources/ParchmentAgent/ActivityText.swift` (create) - "Editing X.swift", "Ran swift test" from tool calls.
- `Sources/ParchmentAgent/PlanProgress.swift` (create) - combine steps, checkboxes and todos into progress and current steps.
- `Sources/ParchmentAgent/StepMatcher.swift` (create) - match todo text to plan steps.
- `Sources/ParchmentAgent/PlanFileRule.swift` (create) - is this path plan-like.
- `Sources/ParchmentAgent/EventInbox.swift` (create) - list, order, read and delete inbox files.
- `Sources/ParchmentAgent/HookInstaller.swift` (create) - hook script text, merge into and remove from settings JSON.
- `Tests/ParchmentCoreTests/TextChangeTests.swift`, `PlanStepTests.swift` (create).
- `Tests/ParchmentAgentTests/*Tests.swift` (create) - one file per source above.

App (`Parchment/`):

- `App/ParchmentApp.swift` (modify) - app delegate adaptor that starts `AgentMonitor` at launch.
- `App/AppDelegate.swift` (create) - starts the monitor.
- `App/ParchmentCommands.swift` (modify) - Connect/Disconnect, Follow Claude toggle, Stop Following.
- `App/PreferenceKey.swift` (modify) - `followClaude` key.
- `Agent/AgentMonitor.swift` (create) - watches the inbox, keeps sessions, maps sessions to plan files, opens and replaces windows.
- `Agent/DirectoryWatcher.swift` (create) - `DispatchSource` watcher for the inbox folder.
- `Agent/FileWatcher.swift` (create) - `DispatchSource` watcher for one file, survives atomic replace.
- `Agent/ConnectClaudeSheet.swift` (create) - shows the settings change and confirms.
- `Agent/PlanActivity.swift` (create) - observable per-file view of the attached session (status, activity, progress, steps, ticker).
- `Editor/AgentEffects.swift` (create) - effect state (ink regions, margin marks, caret, pulsing and filling tasks, helper tags) and timing.
- `Editor/EditorCoordinator.swift` (modify) - file watching, external diff apply, read-only, effects hook-up.
- `Editor/ParchmentTextView.swift` (modify) - `applyExternalText`, draw overlays, display link, follow scrolling.
- `Editor/MarkdownLayoutManager.swift` (modify) - pulsing and filling task circles.
- `Window/EditorController.swift` (modify) - plan steps from lines, attached `PlanActivity`.
- `Window/DocumentWindowView.swift` (modify) - pick pill and progress source.
- `Window/AgentPill.swift` (create) - shimmering status pill and activity ticker.
- `Window/ProgressLine.swift` (modify) - glint while working.
- `project.yml` (modify) - link the `ParchmentAgent` product.
- `README.md` (modify) - "Watching Claude Code plans" section.

## Phases

### Phase 1: Pure logic and tests

- [x] `TextChange.between(old:new:) -> TextChange?` (common prefix and suffix in UTF-16; `oldRange`, `newRange`).
- [x] `PlanSteps.steps(in:text:) -> [PlanStep]` (`range`, `title`, `kind: task(isChecked) | numbered | heading`, `level`).
      Tasks if any exist; else top-level numbered items; else H2/H3 headings (skip the H1 title).
- [x] `AgentEvent` decoding for SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse,
      PostToolUseFailure, Notification, Stop, SubagentStart, SubagentStop. Unknown events and fields are ignored.
- [x] `AgentSession.apply(_:)`: status (working, waiting, done, ended), current activity per agent, todos,
      helpers, plan URL, last edited file and time, recent actions (max 3).
- [x] Todos: `TodoWrite` replaces the list; `TaskCreate` adds (id from `tool_response` if found, else a counter);
      `TaskUpdate` changes status and owner. The agent that sets a todo in progress becomes its owner.
- [x] `ActivityText` for Read, Write, Edit, MultiEdit, Bash (uses `description` when present), Grep, Glob,
      WebFetch, WebSearch, Agent/Task, TodoWrite/Task*, ExitPlanMode, `mcp__server__tool`, and a default.
- [x] `StepMatcher`: normalised word overlap (lowercase, drop short and common words), threshold 0.5.
- [x] `PlanProgress.make(steps:todos:lastEditLocation:)`: done, total, label style (count or step), current
      step indices with owners.
- [x] `PlanFileRule.isPlanLike(path:home:)`.
- [x] `EventInbox`: list `*.json` sorted by creation date then name, read, delete; drop files older than 2 hours.
- [x] `HookInstaller`: script text; `install(into: Data?) -> Data` and `uninstall(from: Data) -> Data`
      (idempotent, keeps other keys and hooks, pretty printed).

Files: `Packages/ParchmentCore/**`
Verify: `swift test --package-path Packages/ParchmentCore` passes locally (if the toolchain is present) and in CI.

### Phase 2: Reload on change and read-only windows

- [ ] `FileWatcher` and per-window watching in `EditorCoordinator` for windows with a `fileURL`.
- [ ] `ParchmentTextView.applyExternalText(_:) -> TextChange?`: replace only the changed range, no undo, keep
      the user's selection and scroll position, restyle, update `document.text` and the controller.
- [ ] Same diff path when SwiftUI hands the coordinator a new document instance for the same URL.
- [ ] `isReadOnly` on the coordinator, driven later by the monitor; revert the NSDocument when it turns off.

Files: `Parchment/Agent/FileWatcher.swift`, `Parchment/Editor/EditorCoordinator.swift`, `Parchment/Editor/ParchmentTextView.swift`
Verify: CI builds. On the Mac: open a file, change it with `echo >> file.md` in Terminal, the window updates
without a "modified" dot.

### Phase 3: Agent monitor, hook installer, window opening

- [ ] `AgentMonitor` (main actor, observable): inbox watcher, sessions keyed by `session_id`, session to plan URL,
      `activity(for: URL) -> PlanActivity?`, stale timer.
- [ ] Open plan files in the background; one window per session; close the old one only if auto-opened.
- [ ] Attach a session to a file the user already has open when the session edits it.
- [ ] `ConnectClaudeSheet` + Connect/Disconnect menu items; write the script (0755) and settings.
- [ ] Stop Following menu item detaches the session from the window.

Files: `Parchment/Agent/*`, `Parchment/App/*`, `project.yml`
Verify: CI builds. On the Mac: Connect, start `claude` in a repo, ask for a plan in plan mode; Parchment opens it
behind the terminal; the window is read-only until the session ends.

### Phase 4: Status pill, ticker and progress line

- [ ] `AgentPill` with states, shimmer (`TimelineView(.animation)` + moving gradient mask), helper count, progress label.
- [ ] Ticker of the last 3 actions above the pill, each fading after 8s.
- [ ] `ProgressLine` takes plan progress while a plan is attached and shows a glint while working.

Files: `Parchment/Window/*`
Verify: CI builds. On the Mac: pill text follows Claude's tools; shimmer stops on "Waiting for you".

### Phase 5: In-text effects

- [ ] `AgentEffects` with display-link timing and Reduce Motion handling.
- [ ] Wet ink and margin marks for each external change.
- [ ] Claude's caret with name tag (main agent "Claude", helpers by `agent_type`).
- [ ] Follow Claude scrolling, paused for 4s after the user scrolls.
- [ ] Pulsing current task circles and the fill animation for newly checked boxes.
- [ ] Helper tags at the end of a current step's first line.

Files: `Parchment/Editor/*`, `Parchment/App/ParchmentCommands.swift`, `Parchment/App/PreferenceKey.swift`
Verify: CI builds. On the Mac: watch a plan being executed; effects show and stop; with Reduce Motion on,
nothing animates.

### Phase 6: CI green, README, review pass

- [ ] Push, fix compile errors until the "Build" workflow is green.
- [ ] README section on connecting and what each signal means.
- [ ] Review pass over the diff.

Files: any
Verify: GitHub Actions "Build" green on the branch.

### Phase 7: User tries it on their Mac

- [ ] The user connects Claude Code and watches a real plan, and reports what feels off.

## Edge cases considered

- **Parchment not running:** hook writes nothing unless the event is plan-related, then launches Parchment in
  the background; the first events after launch are still in the inbox and get read.
- **Old inbox files** (crash, app quit mid-session): dropped when older than 2 hours.
- **Several sessions on one file:** the most recent session wins the window; the pill names it.
- **Plan file deleted or renamed by Claude:** watcher re-opens the path after a short delay; if it is gone, the
  window stays with the last text and the pill says the file is missing.
- **User has unsaved edits in a window when the file changes** (only possible outside plan mode): no reload.
- **Big `Write` payloads** in hook input: written to disk once and deleted after reading; content is ignored.
- **Unknown or changed hook fields:** decoding ignores what it does not know; the feature degrades to fewer
  signals instead of failing.
- **`TaskCreate` id not found in the response:** a local counter is used; later `TaskUpdate`s may not match and
  are ignored.
- **Claude Code sessions started before connecting:** they do not have the hook yet. The Connect sheet says to
  restart running sessions.
- **Existing `~/.claude/settings.json` that is not valid JSON:** do not touch it; show an error with the path.
- **Reduce Motion:** no fades, pulses, shimmer or glint; marks are static and disappear after 4s; scrolling is not animated.
- **Hook speed:** the hook runs before and after every tool call, so it is kept to `cat`, `mv` and `pgrep`.

## Verification

1. `swift test --package-path Packages/ParchmentCore` passes (Phase 1 logic).
2. GitHub Actions "Build" is green and uploads `Parchment.zip`.
3. On the user's Mac: Parchment > Connect to Claude Code…, then in a terminal run `claude` in any repo, ask for a
   plan in plan mode, approve it, and let it work. Parchment opens the plan in the background, the window is
   read-only, the pill and progress line move, edits ink in, checkboxes fill, and helpers are tagged. After the
   session ends the window is editable.

## Open questions

- Exact `tool_response` shape of `TaskCreate` (where the new task id is). Parsed defensively; confirm on the Mac.
- Whether opening a document while Parchment is inactive keeps the terminal in front on macOS 26. Confirm on the Mac.
- Whether NSDocument's own auto-revert fires for these windows. The diff path handles both cases.
