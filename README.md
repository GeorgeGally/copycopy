# Roger

A clipboard history for macOS: every text, image and file you copy, one
keystroke away in the menu bar.

## Download

1. Download `Roger.app` from the [Releases page](https://github.com/GeorgeGally/roger/releases).
2. Drag it into Applications and open it.
3. When macOS asks for Accessibility, turn it on. Roger needs it to paste for
   you; until then Return only copies.

If macOS says it cannot verify the app, right-click it and choose Open.

## Hotkey

Command + Option + Control + V opens the history on the screen you are on.
Change it in Preferences.

![The bezel open on a text item](docs/screenshots/bezel-text.png)

![The bezel open on an image item](docs/screenshots/bezel-image.png)

![The menu-bar menu with text and image rows](docs/screenshots/menu.png)

## Use

- Copy text, an image, or one or more files in Finder.
- Press Command + Option + Control + V to open history on the active screen.
- Press V, Right, or Down to move to an older item. Shift + V, Shift + Right,
  Left, or Up moves back. The shortcut also cycles while the bezel is open.
  Stepping past the newest or oldest item moves to the other end without the
  long slide back.
- Press Return to copy the selected item and paste into the app you were using.
  The bezel reopens on that item, so you can walk through history in order.
- Press Escape to dismiss. Releasing the shortcut modifiers leaves the bezel open.
- Click the menu-bar icon for the 20 most recent items, Clear history,
  Preferences, and Quit. Preferences records a new shortcut when you click the
  field and press a combination. Escape cancels. If another app owns the
  combination, the old shortcut is kept and a message appears.

Pasting needs Accessibility access. The first Return asks for it with the
system dialog; until it is granted the bezel says it copied and cannot paste
yet, and the item is on the clipboard for Command + V. The menu-bar item Allow
Pasting in Accessibility opens System Settings > Privacy & Security >
Accessibility at any time. A build signed with the CopyOver Local Signing
certificate keeps its grant. Without that certificate the app is signed ad-hoc,
so a rebuilt app is not trusted even while an older Roger row shows as
switched on: remove that row with the minus button and add the new app. Every
paste attempt is logged to `~/Library/Application Support/Roger/paste.log`. If
another clipboard app owns the shortcut, quit it and relaunch Roger, or record
a different shortcut in Preferences.

## Storage

History is local in `~/Library/Application Support/Roger/`. `history.json`
holds text and file references. Images are stored beside it as PNG files. Files
are referenced in their original locations, not duplicated; moving or deleting
an original file can make that history entry unusable.

On first launch Roger copies any history it finds in the older
`~/Library/Application Support/CopyOver/` folder, and leaves that folder in
place.

Roger keeps 200 items, moves duplicates to the top, and limits image storage
to 500 MiB by evicting the oldest images. It skips empty text, text over 2 MiB,
images over 40 MiB, and clipboard items marked `org.nspasteboard.ConcealedType`.
Clear history deletes the stored entries and images. It does not erase the
current system clipboard or the original files.

## Build from source

Requires macOS 14 or newer and the Command Line Tools (a Swift toolchain). Xcode
and third-party dependencies are not required.

    ./build.sh          # builds Roger.app in ./dist
    open dist/Roger.app

Run the script from any directory; the app stays in the menu bar and does not
appear in the Dock. The script uses Swift Package Manager and signs with the
CopyOver Local Signing certificate from the login keychain when the certificate
is present, so the Accessibility grant survives a rebuild. Without it the app is
signed ad-hoc and the script says so. To create the certificate, use Keychain
Access (Certificate Assistant > Create a Certificate, type Code Signing, name
CopyOver Local Signing).

    ./scripts/swift-package.sh test -c release
    codesign --verify --strict dist/Roger.app

The tests use temporary storage and named pasteboards. They exercise limits,
eviction, duplicates, persistence, concealed items, all three clipboard types,
and selection wrapping. Live checks should also cover the sticky hotkey,
Return into TextEdit, Escape, Finder copies, and quitting and relaunching.

The package wrapper handles a Command Line Tools installation that contains both
the old and new `SwiftBridging` module maps. It creates a compiler overlay under
`.build/` to hide the duplicate for this build only. It does not modify the SDK
or installed tools. On an unaffected installation, it calls Swift Package
Manager without the overlay.
