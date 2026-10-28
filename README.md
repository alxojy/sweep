# Sweep

A small macOS menu bar app that shows what's using your disk and clears the safe stuff: Xcode DerivedData, old simulators, app caches, and the npm, Yarn, pnpm, Go, Cargo and Homebrew caches, plus `node_modules` and Rust `target/` folders in your projects.

Each item is labelled **Safe**, **Check first** or **Look only**. Look-only items (Docker VM, Rust toolchains, Archives, Downloads) can only be opened in Finder. Click **Clean**, then **Sure?**, to delete.

## Build

```sh
./build.sh && open Sweep.app
```

Needs the Xcode command line tools and macOS 14 or later.
