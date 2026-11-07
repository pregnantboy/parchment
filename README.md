# Parchment

Parchment is a native Markdown editor for the Mac. It edits one pane of plain text and styles it live as you type: the Markdown symbols stay visible but fade back, so headings, lists, quotes, code and tables read like a finished page. It opens and saves ordinary `.md` files, supports several windows, and follows your light or dark appearance.

It is set in an old-style book serif. A reading mode (⇧⌘R) hides the Markdown symbols and locks the text, while checkboxes stay clickable and links open with a click. When the window is wide enough, the outline sits in a panel on the left.

Two effects give it a storybook feel, and each can be switched off in Parchment > Settings:

- **Ink bleed**: new letters land as wet ink and settle (off while Reduce Motion is on).
- **Ornaments**: wax-seal checkboxes, filigree rules, a large first letter, a decorative quote mark and diamond bullets.

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

Tagged versions are on the repository's Releases page. Every push also builds the app on GitHub: open the repository's Actions tab, pick the latest green "Build" run, and download the `Parchment.zip` artifact. Double-click it to get `Parchment.app`, then move that to Applications.

The app is not signed with an Apple developer certificate, so macOS blocks the first launch. Right-click the app and choose Open, then confirm. Or run:

```bash
xattr -dr com.apple.quarantine /Applications/Parchment.app
```

## Releasing

Push a version tag. CI builds that version and publishes it as a GitHub Release with `Parchment.zip` attached:

```bash
git tag v1.0.0
```

```bash
git push origin v1.0.0
```

The tag sets the version the app reports (here 1.0.0). The newest release is always at `releases/latest/download/Parchment.zip` in this repository.

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
  Resources/               Asset catalog
Packages/ParchmentCore/    Markdown parsing and editing logic (Swift package)
project.yml                XcodeGen project spec
docs/plans/                Implementation plan
```

## Running core tests

```sh
swift test --package-path Packages/ParchmentCore
```
