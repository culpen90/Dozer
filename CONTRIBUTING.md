# Contributing to BarHide

Bug reports, feature requests, design work, and code contributions are welcome.

## Bug reports

Open an issue in the [BarHide repository](https://github.com/culpen90/BarHide/issues)
and include the BarHide and macOS versions you are using.

## Feature requests

Open an issue before starting a significant feature so its design and scope can
be agreed on first.

## Design

Contributions that refresh the BarHide icon or visual identity are welcome. The
[original Dozer design resources](https://www.figma.com/file/g5MhiwxR1YFg5vti0tPANa/Dozer)
are available as historical reference.

## Code

BarHide requires macOS 11 or later, Xcode 15 or later, and
[Homebrew](https://brew.sh). Dependencies are managed with Swift Package
Manager and resolve automatically in Xcode.

```shell
git clone https://github.com/culpen90/BarHide.git
cd BarHide
make build
```

The command installs the development tools from the `Brewfile`, generates the
Xcode project, and opens it.

## Pull requests

Describe the change, link any related issues, and add a changelog entry when the
change affects users.
