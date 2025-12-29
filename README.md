# VTool - Vim-style Clipboard Manager for macOS

<p align="center">
  <img src="docs/icon.png" alt="VTool Icon" width="128">
</p>

A powerful, keyboard-driven clipboard manager for macOS with Vim-style navigation, advanced filtering, tag management, and iCloud sync support.

## Features

- 🎹 **Vim-style Navigation** - Navigate with `j`/`k`, jump with `gg`/`G`
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

### Build from Source
```bash
git clone https://github.com/seongminhwan/viclip.git
cd viclip
swift build -c release
./scripts/package.sh
```

## Keyboard Shortcuts

### Global Hotkey
| Shortcut | Action |
|----------|--------|
| `⌘⇧V` | Open/Close VTool (configurable) |

---

### NORMAL Mode (Main Window)

#### Navigation
| Shortcut | Action |
|----------|--------|
| `j` | Move down |
| `k` | Move up |
| `gg` | Jump to top |
| `G` | Jump to bottom |
| `1-9` | Quick select item 1-9 |

#### Actions
| Shortcut | Action |
|----------|--------|
| `⏎` | Paste selected item |
| `⌘⏎` | Paste as plain text |
| `d` | Delete item |
| `⌃F` | Toggle favorite |
| `v` | Quick preview |
| `q` | Add to paste queue |
| `p` | Locate in timeline (position mode) |

#### Mode Switching
| Shortcut | Action |
|----------|--------|
| `f` | Enter SEARCH mode (focus search input) |
| `⌘F` | Open Advanced Filter panel |
| `F` (Shift+f) | Open type filter |
| `:` | Open command menu |
| `⇧T` | Toggle TAG panel |
| `ESC` | Close popup / Clear filter |

---

### SEARCH Mode

| Shortcut | Action |
|----------|--------|
| Type | Search clipboard items |
| `⏎` | Paste first result |
| `⌃P` | Exit search and locate item |
| `ESC` | Exit to NORMAL mode |

---

### PREVIEW Mode

| Shortcut | Action |
|----------|--------|
| `j` | Scroll down |
| `k` | Scroll up |
| `⌃D` | Half page down |
| `⌃U` | Half page up |
| `⌘C` | Copy content |
| `o` | OCR extract text (for images) |
| `ESC` | Close preview |

---

### TAG Mode (Tag Panel Open)

#### Tag List Navigation
| Shortcut | Action |
|----------|--------|
| `j` | Move down in tag list |
| `k` | Move up in tag list |
| `⏎` | Filter by selected tag |
| `l` | Switch to history list |
| `c` | Create new tag |
| `r` | Rename selected tag |
| `d` | Delete selected tag |
| `ESC` | Close tag panel |

#### History List (when focused)
| Shortcut | Action |
|----------|--------|
| `j` | Move down |
| `k` | Move up |
| `Space` | Toggle tag on item |
| `h` | Return to tag list |

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

#### Keyword Section (when expanded)
| Shortcut | Action |
|----------|--------|
| `⌃R` | Toggle Regex |
| `⌃C` | Toggle Case Sensitive |

#### Date Range Section (when expanded)
| Shortcut | Action |
|----------|--------|
| `⌃A` | All Time |
| `⌃L` | Last Hour |
| `⌃T` | Today |
| `⌃Y` | Yesterday |
| `⌃W` | Last 7 Days |
| `⌃M` | Last 30 Days |
| `⌃C` | Custom Range |
| `⌃F` | Focus From date (in Custom) |

#### List Sections (Content Type / Source App / Tags)
| Shortcut | Action |
|----------|--------|
| `j` | Move down |
| `k` | Move up |
| `Space` | Toggle selection |

---

### POSITION Mode

| Shortcut | Action |
|----------|--------|
| `j` | Expand range down |
| `k` | Expand range up |
| `⌘⏎` | Paste selected range |
| `ESC` | Exit position mode |

---

### Type Filter Mode (`F`)

| Shortcut | Action |
|----------|--------|
| `1` | Filter: Text only |
| `2` | Filter: Images only |
| `3` | Filter: Files only |
| `4` | Filter: Rich Text only |
| `a` | Show all types |
| `ESC` | Exit filter mode |

---

## Mode Indicators

The mode indicator in the top-left shows current state:

| Indicator | Color | Description |
|-----------|-------|-------------|
| `NORMAL` | 🟢 Green | Default browsing mode |
| `SEARCH` | 🟠 Orange | Search input focused |
| `TAG` | 🔵 Teal | Tag panel open |
| `COMMAND` | 🟣 Purple | Command menu open |
| `POSITION` | 🔵 Cyan | Position/range mode |
| `FILTERED` | 🟡 Yellow | Search or filter active |

---

## Settings

Access settings via Menu Bar → VTool → Preferences (`⌘,`)

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
