# Parchment

Parchment is a native Markdown editor for the Mac. It edits one pane of plain text and styles it live as you type: the Markdown symbols stay visible but fade back, so headings, lists, quotes, code and tables read like a finished page. It opens and saves ordinary `.md` files, supports several windows, and follows your light or dark appearance.

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

Every push builds the app on GitHub. Open the repository's Actions tab, pick the latest green "Build" run, and download the `Parchment.zip` artifact. Double-click it to get `Parchment.app`, then move that to Applications.

The app is not signed with an Apple developer certificate, so macOS blocks the first launch. Right-click the app and choose Open, then confirm. Or run:

```bash
xattr -dr com.apple.quarantine /Applications/Parchment.app
```

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
| Show outline | ⇧⌘O |
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
