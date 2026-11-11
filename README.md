# Parchment

Parchment is a native Markdown editor for the Mac. It edits one pane of plain text and styles it live as you type: the Markdown symbols stay visible but fade back, so headings, lists, quotes, code and tables read like a finished page. It opens and saves ordinary `.md` files, supports several windows, and follows your light or dark appearance.

It is set in an old-style book serif. A reading mode (⇧⌘R) hides the Markdown symbols and locks the text, while checkboxes stay clickable and links open with a click. When the window is wide enough, the outline sits in a panel on the left.

Text size and line spacing are set in Parchment > Settings (15 pt and 1.5 by default; line spacing goes from 0.8 to 2.2).

Two effects give it a storybook feel, and each can be switched off in Parchment > Settings:

- **Ink bleed**: new letters land as wet ink and settle (off while Reduce Motion is on).
- **Ornaments**: wax-seal checkboxes, filigree rules, a decorative quote mark and diamond bullets.

## Requirements

- macOS 26 or later
- Xcode 27 (Swift 6.4)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build and run

```sh
brew install xcodegen
xcodegen generate
open Parchment.xcodeproj
```

Then press ⌘R in Xcode.

## Download a build without Xcode

Released versions are on the repository's Releases page: download `Parchment.dmg`, open it, and drag Parchment onto the Applications shortcut next to it. Every push also builds the app on GitHub: open the repository's Actions tab, pick the latest green "Build" run, and download the `Parchment.dmg` artifact.

The app is not signed with an Apple developer certificate, so macOS blocks the first launch. Right-click the app and choose Open, then confirm. Or run:

```bash
xattr -dr com.apple.quarantine /Applications/Parchment.app
```

## Releasing

Publish a release on GitHub: on the Releases page choose **Draft a new release**, pick or create a tag like `v1.0.0`, write the notes and click **Publish release**. CI then builds that version and attaches `Parchment.dmg` to the release a few minutes later.

From a terminal, this does the same:

```bash
gh release create v1.0.0 --generate-notes
```

The tag sets the version the app reports (here 1.0.0). Pushing a tag alone publishes nothing; the release is what starts the build. The newest release is always at `releases/latest/download/Parchment.dmg` in this repository.

## Watching Claude Code plans

Parchment can show the plan Claude Code is working on, live, when Claude Code runs in a terminal on the same Mac.

1. Open **Parchment > Settings** (⌘,) and click **Connect…** under Claude Code. Parchment shows the hook it adds to `~/.claude/settings.json` and saves a backup next to it. Restart any Claude Code sessions that are already running. If you connected with an older Parchment, Settings shows **Update…** instead: it replaces the hook with one that also reports what Claude says and asks.
   It also adds a short note to `~/.claude/CLAUDE.md` asking Claude to keep each task's box up to date (see below).
2. Work with Claude Code as usual. When it writes a plan (in plan mode, or any Markdown file in a `plans` folder or with "plan" in its name), Parchment opens it in the background, one window per session.

While Claude works on the file, the window is read-only and shows:

- **The status pill:** who is working (and how many helpers), what they are doing, and progress such as "6 of 9" (from checkboxes or Claude's todo list) or "Step 3 of 7" (a guess from where Claude is editing). Anything that runs longer than ten seconds gets a timer, like "Running the tests 42s". A second line carries Claude's own words: the sentence it is writing while it works, and what its last message came down to once it stops (its closing question, if it asked one). When Claude waits, the pill says what for: "Needs your permission to run swift test", "Asks you: Which color?", "Waiting for you to approve the plan", "Waiting on 1 background task" or "Stopped: Rate limit reached". It shimmers while Claude works and goes still when it waits, on "Done", or on "Last update 6 min ago" (shown only when nothing is running).
- **The activity timeline:** click the pill (or press ⇧⌘A) for the whole story of the session: what you asked, what Claude said, every action with how long it took and whether it worked (with the error if it failed), and what each helper was sent to do and reported back. The top shows a summary of the turn, such as "Working for 3m 05s · 4 files edited · 6 commands · 1 failed", and the helpers at work right now.
- **Recent actions** above the pill, such as "Edited StatusPill.swift ✓", fading after a few seconds.
- **The progress bar** along the top, in the pill and in the timeline has one piece per top-level task. A piece fills as the task's sub-steps (checkboxes indented under it) are ticked. A task marked in progress counts as half done, or as far as Claude's own todo list has got when that list breaks the task down. Blocked tasks are drawn dark. The bar can move back when Claude unticks a box or adds tasks. A glint runs along it while Claude works, and it is fainter when progress is only a guess ("Step 3 of 7").
- **In the text:** new text inks in, changed lines get a vermilion mark in the margin, Claude's caret shows where it last wrote, the current task's circle pulses, ticked boxes fill in, and steps a helper works on are tagged with its name.

### Task states

Plans can mark each task with one of four boxes. Claude updates them as it works, and you can too:

| Markdown | Meaning | Shown as |
|---|---|---|
| `- [ ]` | Not started | Empty circle |
| `- [/]` | In progress | Half-filled vermilion circle |
| `- [!]` | Blocked | Vermilion circle with a bar. Add the reason after the task, like `(blocked: needs an API key)` |
| `- [x]` | Done | Filled circle (a wax seal with Ornaments on), text struck through |

Clicking a circle ticks it, or unticks a done task. `[/]` and `[!]` are a common extension of Markdown: other apps, including GitHub, show them as plain text.

**View > Follow Claude** scrolls to each change (it pauses for a few seconds after you scroll). **View > Stop Following Claude** makes the window an ordinary editable document. The window also becomes editable when the session ends. Turning on Reduce Motion in System Settings stops all the animation.

To undo the setup, click **Disconnect…** in the same place; it removes only Parchment's hook and its note in `CLAUDE.md`.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Bold | ⌘B |
| Italic | ⌘I |
| Strikethrough | ⇧⌘X |
| Inline code | ⌥⌘C |
| Link | ⌘K |
| Body text | ⌘0 |
| Heading 1 to 6 | ⌘1 to ⌘6 |
| Toggle task | ⇧⌘L |
| Indent | ⌘] |
| Outdent | ⌘[ |
| Focus mode | ⇧⌘F |
| Typewriter mode | ⇧⌘T |
| Reading mode | ⇧⌘R |
| Show or hide outline | ⇧⌘O |
| Bigger text | ⌘+ |
| Smaller text | ⌘− |
| Actual size | ⌥⌘0 |

## Project layout

```
Parchment/                 App target
  App/                     App entry point, menu commands, preferences
  Document/                MarkdownDocument and the Markdown file type
  Theme/                   Colors, fonts and layout metrics
  Editor/                  Text view, styling and drawing
  Window/                  Document window, status pill, outline
  Agent/                   Following Claude Code: hook inbox, file watching, connect dialogs
  Resources/               Asset catalog
Packages/ParchmentCore/    Markdown parsing and editing logic, plus ParchmentAgent
                           (Claude Code hook events, sessions, plan progress)
project.yml                XcodeGen project spec
docs/plans/                Implementation plan
```

## Running core tests

```sh
swift test --package-path Packages/ParchmentCore
```
