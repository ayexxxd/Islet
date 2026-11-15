# Islet

A Dynamic Island for the Mac notch, written in Swift and SwiftUI. No dependencies.

## Build and run

Requires macOS 13 or later and Xcode (or the Xcode command line tools).

    chmod +x build.sh
    ./build.sh run

This produces `build/Islet.app`. To edit in Xcode, open `Package.swift`.
Running straight from Xcode works for UI work, but media control needs the
bundled app, because the Automation permission text lives in `Info.plist`.

## What it does

- Hover (or click) the notch and it springs open. Move away and it closes.
- Media tab. Artwork, title, scrubbing, previous, play, next for Spotify and Apple Music.
- Notes tab. Multiple quick notes, saved to `~/Library/Application Support/Islet/notes.json`.
- Tools tab. Clipboard history and a shelf you can drop files on.
- Header. Keep awake toggle, pin, settings.
- Closed state. Artwork and animated bars beside the notch while music plays,
  and a small toast when the track changes.
- Global shortcuts. Control Option Space toggles the island, Control Option N starts a quick note.
- Adjustable open size and notch outline width in Settings.
- Liquid Glass body on macOS 26 and later, switchable to solid black in Settings.

## Permissions

The first time a player is detected, macOS asks to let Islet control Spotify or Music.
Allow it, or change it later in System Settings, Privacy and Security, Automation.

## Layout

    Sources/Islet/App        entry point, app delegate, menu bar item
    Sources/Islet/Core       panel, mouse tracking, island state, settings
    Sources/Islet/Features   media, notes, clipboard, shelf, keep awake
    Sources/Islet/Views      SwiftUI views and animations
