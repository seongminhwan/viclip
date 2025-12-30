# Viclip - Vim-style Clipboard Manager for macOS

<p align="center">
  <img src="logo.png" alt="Viclip Icon" width="128">
</p>

A powerful, keyboard-driven clipboard manager for macOS with Vim-style navigation, advanced filtering, tag management, and iCloud sync support.

## Features

- 🎹 **Vim-style Navigation** - Navigate with `j`/`k`, use GOTO mode for quick access
- 🔍 **Advanced Filtering** - Search by keyword, content type, source app, date range, tags
- 🏷️ **Tag Management** - Organize clipboard items with custom tags
- ⭐ **Favorites** - Mark important items for quick access
- 📋 **Paste Queue** - Queue multiple items for sequential pasting
- 👁️ **Quick Preview** - Preview images, rich text, and code with syntax highlighting
- 🔄 **iCloud Sync** - Sync clipboard history across all your Macs
- 🌙 **Dark Mode** - Beautiful dark theme support

## Installation

### Download
Download the latest release from [GitHub Releases](https://github.com/seongminhwan/viclip/releases).

> ⚠️ **First Run - "App is damaged" Error**  
> Since the app is not signed, macOS may block it. Run this in Terminal:
> ```bash
> xattr -cr /Applications/Viclip.app
> ```

### Build from Source
```bash
git clone https://github.com/seongminhwan/viclip.git
cd viclip
swift build -c release
./scripts/package.sh
```

---

## Modal Design Philosophy

Viclip adopts a **modal interface** inspired by Vim, where different modes enable different sets of keyboard shortcuts. This design allows:

- **Efficient keyboard-only operation** - No need to reach for the mouse
- **Context-aware shortcuts** - Same keys do different things in different modes
- **Reduced cognitive load** - Each mode has a focused set of actions
- **Progressive complexity** - Basic operations work in NORMAL mode; advanced features are in specialized modes

### Mode Overview

| Mode | Purpose | Indicator Color |
|------|---------|----------------|
| **NORMAL** | Browse and select items | 🟢 Green |
| **SEARCH** | Type to filter items | 🟠 Orange |
| **FILTERED** | Active search/filter results | 🟡 Yellow |
| **GOTO** | Quick jump and paste by shortcut | (sub-state of NORMAL) |
| **TAG** | Manage and filter by tags | 🔵 Teal |
| **PREVIEW** | Full-screen item preview | - |
| **POSITION** | Locate item in timeline | 🔵 Cyan |
| **COMMAND** | Execute commands | 🟣 Purple |

### Mode Transitions

```
                    ┌─────────────────────────────────────┐
                    │              NORMAL                 │
                    │  (default mode, VIM navigation)     │
                    └─────────────────────────────────────┘
                      │    │    │    │    │    │    │
         f or /       │    │    │    │    │    │    │  g
           ┌──────────┘    │    │    │    │    │    └──────────┐
           ▼               │    │    │    │    │               ▼
      ┌─────────┐          │    │    │    │    │          ┌─────────┐
      │ SEARCH  │          │    │    │    │    │          │  GOTO   │
      │ (type)  │          │    │    │    │    │          │ (1-9,   │
      └─────────┘          │    │    │    │    │          │  a-z)   │
           │               │    │    │    │    │          └─────────┘
           │ ESC/⏎         │    │    │    │    │               │
           └───────────────┼────┼────┼────┼────┼───────────────┘
                           │    │    │    │    │          ESC/action
                     :     │    │  ⇧T│    │ p  │
          ┌────────────────┘    │    │    │    └────────────────┐
          ▼                     │ v  │    │                     ▼
     ┌─────────┐                │    │    │                ┌─────────┐
     │ COMMAND │                │    │    │                │POSITION │
     │  menu   │                ▼    ▼    │                │  mode   │
     └─────────┘           ┌─────────────┐│                └─────────┘
          │                │   PREVIEW   ││                     │
          │ ESC            │   (v, ESC)  ││                     │ ESC
          └────────────────┴─────────────┴┴─────────────────────┘
                                   │
                              ┌────┴────┐
                              │   TAG   │
                              │  panel  │
                              └─────────┘
```

---

## Keyboard Shortcuts

### Global Hotkey
| Shortcut | Action |
|----------|--------|
| `⌘⇧V` | Open/Close Viclip (configurable) |

---

### NORMAL Mode (Main Window)

The default mode for browsing clipboard history.

#### Navigation
| Shortcut | Action |
|----------|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `⌃D` | Half page down |
| `⌃U` | Half page up |
| `g` | Enter GOTO mode (quick jump/paste) |

#### Actions
| Shortcut | Action |
|----------|--------|
| `⏎` | Paste selected item |
| `⌘⏎` | Paste as plain text |
| `d` | Delete item |
| `R` | Rename / set alias |
| `⌃F` | Toggle favorite |
| `v` | Quick preview |
| `q` | Add to paste queue |
| `p` | Locate in timeline (position mode) |
| `o` | Open in external app |

#### Mode Switching
| Shortcut | Action |
|----------|--------|
| `f` / `/` | Enter SEARCH mode |
| `⌘F` | Open Advanced Filter panel |
| `F` (Shift+f) | Open type filter |
| `:` | Open command menu |
| `⇧T` | Toggle TAG panel |
| `⇧P` | Toggle pin |
| `t` | Tag current item |
| `?` | Show help panel |
| `ESC` | Close popup / Clear filter |

---

### GOTO Mode

A quick-action sub-mode for rapid item selection. When active, visible items display shortcut badges.

| Shortcut | Action |
|----------|--------|
| `1-9`, `a-z`, `A-Z` | Paste visible item at that position |
| `g` | Scroll to top (then exit) |
| `G` | Scroll to bottom (then exit) |
| `j` / `k` | Navigate up/down |
| `⌃D` / `⌃U` | Half page down/up |
| `⌘D` / `⌘U` | Scroll preview panel |
| `ESC` | Exit GOTO mode |

---

### SEARCH Mode

Active when the search input is focused. Type to filter items in real-time.

| Shortcut | Action |
|----------|--------|
| Type | Filter clipboard items |
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `⏎` (first) | Exit search mode |
| `⏎` (second) | Paste selected item |
| `⌃P` | Exit search and locate item |
| `ESC` | Exit to NORMAL mode |

---

### PREVIEW Mode

Full-screen preview of the selected item's content.

| Shortcut | Action |
|----------|--------|
| `j` | Scroll down |
| `k` | Scroll up |
| `⌘D` | Half page down |
| `⌘U` | Half page up |
| `⌘C` | Copy content |
| `o` | OCR extract text (for images) |
| `ESC` / `v` | Close preview |

---

### TAG Mode (Tag Panel Open)

Manage tags and filter items by tag.

#### Tag List (left panel focused)
| Shortcut | Action |
|----------|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Space` | Toggle tag selection |
| `n` | Create new tag |
| `r` | Rename tag |
| `d` | Delete tag |
| `⇧P` | Toggle tag pin |
| `l` / `⏎` | Focus history list |
| `ESC` | Close tag panel |

#### History List (right panel focused)
| Shortcut | Action |
|----------|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `⏎` | Paste selected |
| `t` | Tag current item |
| `h` / `ESC` | Return to tag list |

---

### POSITION Mode

Locate and view an item in its original timeline position.

| Shortcut | Action |
|----------|--------|
| `j` | Expand range down |
| `k` | Expand range up |
| `⌘⏎` | Paste selected range |
| `ESC` | Exit position mode |

---

### Advanced Filter Panel (`⌘F`)

#### Global Shortcuts
| Shortcut | Action |
|----------|--------|
| `⌘K` | Toggle Keyword section |
| `⌘C` | Toggle Content Type section |
| `⌘S` | Toggle Source App section |
| `⌘T` | Toggle Tags section |
| `⌘D` | Toggle Date Range section |
| `⌘O` | Toggle Options section |
| `⌘R` | Reset all filters |
| `⌘⏎` | Apply filter |
| `ESC` | Close panel |

#### Keyboard Shortcuts in Sections
| Shortcut | Action |
|----------|--------|
| `j` / `k` | Navigate list items |
| `Space` | Toggle selection |
| `⌃R` | Toggle Regex (Keyword) |
| `⌃C` | Toggle Case Sensitive (Keyword) |

---

### Type Filter Mode (`F`)

Quick filter by content type.

| Shortcut | Action |
|----------|--------|
| `1` | Text only |
| `2` | Images only |
| `3` | Files only |
| `4` | Rich Text only |
| `a` | Show all types |
| `ESC` | Exit filter mode |

---

## Settings

Access settings via Menu Bar → Viclip → Preferences (`⌘,`)

- **General**: Global hotkey, startup options, auto-cleanup
- **Appearance**: Theme, preview settings
- **Hotkeys**: Customize all keyboard shortcuts
- **Privacy**: Excluded apps, sensitive content
- **Storage**: History limits, large file storage
- **Sync**: iCloud sync settings

---

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

---

**Made with ❤️ for keyboard enthusiasts**
