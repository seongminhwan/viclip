# VTool - Mac Clipboard Manager

[![Build](https://github.com/seongminhwan/viclip/actions/workflows/build.yml/badge.svg)](https://github.com/seongminhwan/viclip/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful native macOS clipboard manager with VIM-style navigation, iCloud sync, and sequential pasting.


## Features

- 📋 **Clipboard History** - Automatically records all copied content
- 🔍 **Smart Search** - Filter history with context-aware search (shows when & where you copied)
- ⌨️ **VIM Navigation** - Use j/k, gg/G, and quick select (1-9)
- 📑 **Sequential Paste** - Copy multiple items and paste them in order
- ⭐ **Favorites & Groups** - Organize frequently used snippets
- ☁️ **iCloud Sync** - Sync across all your Macs
- 🔒 **Privacy Filter** - Exclude password managers and sensitive content
- 🖼️ **Image Support** - Store and preview copied images

## Requirements

- macOS 12.0 or later
- Xcode 15.0 or later (for development)
- Apple Developer account (optional, for iCloud sync)

## Installation

### From Source

```bash
# Clone the repository
cd /path/to/vtool

# Build with Swift Package Manager
swift build -c release

# Or open in Xcode
open Package.swift
```

### Using Xcode

1. Open `Package.swift` in Xcode
2. Select your signing team
3. Build and run (⌘+R)

## Usage

### Global Hotkey

- `⌘+Shift+V` - Toggle VTool popup

### VIM Keybindings

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `gg` | Jump to top |
| `G` | Jump to bottom |
| `Enter` | Paste selected item |
| `d` | Delete item |
| `f` | Toggle favorite |
| `/` | Enter search mode |
| `1-9` | Quick select |
| `Esc` | Close / Cancel |

### Sequential Pasting

1. Open VTool (`⌘+Shift+V`)
2. Click `+` button on items to add to queue
3. Each subsequent paste will use the next item in queue

## Configuration

Open Settings from the menu bar icon to configure:

- **General** - History limit, launch at login
- **Hotkeys** - Customize global shortcuts
- **Privacy** - Exclude apps and keywords
- **Sync** - Enable/disable iCloud sync

## Privacy

VTool respects your privacy:

- All data is stored locally by default
- Password managers are excluded automatically
- iCloud sync is opt-in
- No analytics or tracking

## Development

### Project Structure

```
VTool/
├── Sources/VTool/
│   ├── VToolApp.swift          # App entry point
│   ├── Models/
│   │   └── ClipboardItem.swift # Data models
│   ├── Services/
│   │   ├── ClipboardMonitor.swift
│   │   ├── VIMEngine.swift
│   │   ├── SequentialPaster.swift
│   │   └── PrivacyFilter.swift
│   ├── Persistence/
│   │   ├── ClipboardStore.swift
│   │   └── CloudKitSync.swift
│   ├── Views/
│   │   ├── PopupWindowView.swift
│   │   ├── ClipboardItemRow.swift
│   │   └── PreferencesView.swift
│   └── Resources/
│       ├── Info.plist
│       └── VTool.entitlements
└── Package.swift
```

### Dependencies

- [HotKey](https://github.com/soffes/HotKey) - Global hotkeys
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Hotkey UI
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) - Launch at login

## License

MIT License
