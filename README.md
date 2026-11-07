# Sweep

A small macOS menu bar app that shows what's using your disk and clears the safe stuff: Xcode DerivedData, old simulators, app caches, the npm, Yarn, pnpm, Go, Cargo, Gradle, uv and Homebrew caches, unused Nix store paths and old Claude Code temp files, plus `node_modules`, Rust `target/` and Flutter `build/` and `.dart_tool` folders in your projects.

Each item is labelled **Safe**, **Check first** or **Look only**. Look-only items (Docker VM, Rust toolchains, Archives, Downloads) can only be opened in Finder. Click **Clean**, then **Sure?**, to delete.

## Build

```sh
./build.sh && open Sweep.app
```

Needs the Xcode command line tools and macOS 14 or later.
