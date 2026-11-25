# Lunchr

Opens apps. Nothing else. Swift, no dependencies, macOS 14+.

## Install

```sh
./build.sh install    # build, copy to /Applications, start
swift test
```

Use ⌘Space: turn off System Settings › Keyboard › Keyboard Shortcuts › Spotlight › Show Spotlight search, then Lunchr Settings › General › Use ⌘Space instead. Until then the shortcut is ⌥Space.

## Keys

| Key | |
|---|---|
| ↑ ↓ / Tab | move |
| ↩ | open (and remember it for this search) |
| ⌘↩ | open and pin it to this search |
| ⌘H | hide the app from results |
| ⌘, | Settings |
| esc | close |

Right-click a result to pin, unpin or hide it.

## Order

1. Pinned for this search
2. Last picked for this search
3. Full name typed
4. Pinned or picked for a longer or shorter version of this search (2+ letters)
5. Match: start of name, start of a word, initials, middle of a word. Most used first inside each.

Loose matches only show when nothing better does.

## Themes

Settings › Appearance › Save a Copy to Edit, or put a `.json` in `~/Library/Application Support/Lunchr/Themes`. Changes show on save. Every field is optional:

| Field | Values |
|---|---|
| `name`, `dark` | text, true/false |
| `background`, `text`, `secondaryText`, `accent`, `selection`, `selectedText`, `border` | `#RRGGBB` or `#RRGGBBAA` |
| `opacity` | 0 (only blur) to 1 (solid) |
| `blur` | `none` `soft` `frosted` `heavy` `glass` (glass needs macOS 26) |
| `font` | `system` `rounded` `mono` `serif` or a font family |
| `cornerRadius`, `querySize`, `rowSize`, `iconSize`, `width` | points |

A file named after a built-in (`graphite.json`) replaces it.

## Reveal

Settings › Appearance › Reveal: Off, Pop, or Pop and glow (default; the glow is the theme's `accent`, or white on light themes). With Reduce Motion on it only fades.

## Development

Debug builds only, `LUNCHR_HOME` keeps your real settings out of it:

```sh
swift build
LUNCHR_HOME=/tmp/lunchr LUNCHR_PREVIEW=te LUNCHR_SNAPSHOT=out.png .build/debug/Lunchr
LUNCHR_HOME=/tmp/lunchr LUNCHR_SETTINGS=1 LUNCHR_SNAPSHOT=out.png .build/debug/Lunchr
LUNCHR_HOME=/tmp/lunchr LUNCHR_OPEN=calculator .build/debug/Lunchr
```

Snapshots don't include the blur; the window server draws it. To see it, capture the reveal over a striped window:

```sh
LUNCHR_HOME=/tmp/lunchr LUNCHR_PREVIEW= LUNCHR_FRAMES=/tmp .build/debug/Lunchr
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): use, copy and change it for any noncommercial purpose, and keep the copyright notice with every copy. No commercial use.
