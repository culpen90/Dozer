# BarHide

BarHide keeps a crowded macOS menu bar tidy by hiding icons until you need them.

> [!NOTE]
> BarHide is an independently maintained fork of the original
> [Mortennn/Dozer](https://github.com/Mortennn/Dozer) project.

## Build from source

BarHide requires macOS 11 or later, Xcode 15 or later, and
[Homebrew](https://brew.sh). The repository does not currently publish a
Homebrew cask or a prebuilt release.

```shell
git clone https://github.com/culpen90/BarHide.git
cd BarHide
make build
```

The command installs the development tools from the `Brewfile`, generates
`BarHide.xcodeproj`, and opens it in Xcode. Select the `BarHide` scheme, then
choose **Product → Run** to compile and launch the app.

## BarHide icons

There are two or three control icons, numbered from right to left:

1. The first can be positioned anywhere and acts as a point of interaction.
2. The second and everything to its left are hidden or shown when you click a BarHide icon.
3. The optional remove icon and everything to its left are hidden or shown when you Option-click a BarHide icon.

## Usage

- Move the icons you normally want hidden to the left of the second BarHide icon.
- Move less frequently used icons to the left of the optional third BarHide icon.
- Hold Command (`⌘`) while dragging to reposition menu bar icons.

## Interactions

- Left-click a BarHide icon to hide or show the first group of menu bar icons.
- Option-left-click a BarHide icon to show the optional second group.
- Right-click a BarHide icon to open settings.

## Requirements

macOS 11 or later (Big Sur or newer).
