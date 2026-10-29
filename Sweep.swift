// Sweep: a tiny menu bar tool that shows what is using disk space and clears the safe stuff.
import AppKit
import SwiftUI

// MARK: - Model

enum Safety: Int, Comparable {
    case safe, review, keep
    static func < (a: Safety, b: Safety) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: "Safe"
        case .review: "Check first"
        case .keep: "Look only"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .keep: .secondary
        }
    }
}

enum Action {
    /// Delete everything inside these folders, keeping the folders themselves.
    case emptyFolders
    /// Delete the folders themselves.
    case deleteFolders
    /// Run a shell command through a login shell, so PATH has brew, go, npm and the rest.
    case command(String)
    /// Nothing to clean here; just open it in Finder.
    case reveal
}

struct Target: Identifiable {
    let id: String
    let name: String
    let note: String
    let paths: [URL]
    let safety: Safety
    let action: Action
    var bytes: Int64?
}

private let home = FileManager.default.homeDirectoryForCurrentUser

private func at(_ path: String) -> URL { home.appendingPathComponent(path) }

private func knownTargets() -> [Target] {
    [
        Target(id: "derived", name: "Xcode DerivedData", note: "Build output. Xcode rebuilds it on the next build.",
               paths: [at("Library/Developer/Xcode/DerivedData")], safety: .safe, action: .emptyFolders),
        Target(id: "simunavail", name: "Old simulators", note: "Simulators for runtimes that are no longer installed.",
               paths: unavailableSimulators(), safety: .safe,
               action: .command("xcrun simctl delete unavailable")),
        Target(id: "simcache", name: "Simulator caches", note: "Rebuilt automatically.",
               paths: [at("Library/Developer/CoreSimulator/Caches")], safety: .safe, action: .emptyFolders),
        Target(id: "devicesupport", name: "iOS DeviceSupport", note: "Debug symbols for phones you've plugged in. Re-copied on the next connect.",
               paths: [at("Library/Developer/Xcode/iOS DeviceSupport"), at("Library/Developer/Xcode/watchOS DeviceSupport")],
               safety: .safe, action: .emptyFolders),
        Target(id: "caches", name: "App caches", note: "~/Library/Caches. Apps rebuild these, though some may start slower once.",
               paths: [at("Library/Caches")], safety: .safe, action: .emptyFolders),
        Target(id: "npm", name: "npm cache", note: "Packages are downloaded again when needed.",
               paths: [at(".npm/_cacache")], safety: .safe, action: .command("npm cache clean --force")),
        Target(id: "yarn", name: "Yarn cache", note: "Packages are downloaded again when needed.",
               paths: [at(".yarn/berry/cache"), at("Library/Caches/Yarn")], safety: .safe, action: .emptyFolders),
        Target(id: "go", name: "Go module + build cache", note: "Modules are downloaded again on the next build.",
               paths: [at("go/pkg/mod"), at("Library/Caches/go-build")], safety: .safe,
               action: .command("go clean -modcache -cache")),
        Target(id: "cargo", name: "Cargo registry cache", note: "Crates are downloaded again on the next build.",
               paths: [at(".cargo/registry/cache"), at(".cargo/registry/src")], safety: .safe, action: .emptyFolders),
        Target(id: "brew", name: "Homebrew downloads", note: "Old bottles and downloads.",
               paths: [at("Library/Caches/Homebrew")], safety: .safe, action: .command("brew cleanup -s --prune=all")),
        Target(id: "pnpm", name: "pnpm store", note: "Existing node_modules keep working; the next install downloads packages again.",
               paths: [at("Library/pnpm/store")], safety: .safe, action: .emptyFolders),
        Target(id: "simdelete", name: "Simulators", note: "Deletes every simulator and its data. Add new ones in Xcode when you need them.",
               paths: [at("Library/Developer/CoreSimulator/Devices")], safety: .review,
               action: .command("xcrun simctl shutdown all; xcrun simctl delete all")),
        Target(id: "trash", name: "Trash", note: "Gone for good once emptied.",
               paths: [at(".Trash")], safety: .review, action: .emptyFolders),
        Target(id: "rustup", name: "Rust toolchains", note: "Remove toolchains you don't use with `rustup toolchain uninstall`.",
               paths: [at(".rustup/toolchains")], safety: .keep, action: .reveal),
        Target(id: "colima", name: "Colima / Docker VM", note: "All your containers and images. Prune from Docker, don't delete this folder.",
               paths: [at(".colima")], safety: .keep, action: .reveal),
        Target(id: "archives", name: "Xcode Archives", note: "Builds you've shipped. Keep the ones you might need to symbolicate.",
               paths: [at("Library/Developer/Xcode/Archives")], safety: .keep, action: .reveal),
        Target(id: "downloads", name: "Downloads", note: "Your files. Sort them yourself.",
               paths: [at("Downloads")], safety: .keep, action: .reveal),
    ]
}

/// Device folders of simulators whose runtime is gone, which is all `simctl delete unavailable` removes.
private func unavailableSimulators() -> [URL] {
    let json = run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"])
    guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let byRuntime = root["devices"] as? [String: [[String: Any]]] else { return [] }
    return byRuntime.values.flatMap { $0 }.compactMap { $0["udid"] as? String }
        .map { at("Library/Developer/CoreSimulator/Devices/\($0)") }
}

/// Folders where project build output (node_modules, Rust target/) gets found.
private let projectRoots = ["code", "orca", "Developer", "Projects", "src"].map(at)

// MARK: - Disk helpers

/// Allocated size in bytes, via `du`, which is quick and copes with unreadable files.
private func diskUsage(_ urls: [URL]) -> Int64 {
    let existing = urls.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
    guard !existing.isEmpty else { return 0 }
    let out = run("/usr/bin/du", ["-sk"] + existing)
    return out.split(separator: "\n").reduce(0) { sum, line in
        sum + (Int64(line.split(separator: "\t").first ?? "") ?? 0) * 1024
    }
}

@discardableResult
private func run(_ exe: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// Runs a command through a login shell, so PATH has brew, go, npm and the rest. Returns the error if it fails.
private func shell(_ cmd: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", cmd]
    let pipe = Pipe()
    p.standardOutput = FileHandle.nullDevice
    p.standardError = pipe
    do { try p.run() } catch { return error.localizedDescription }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus != 0 else { return nil }
    let lastLine = String(decoding: data, as: UTF8.self).split(separator: "\n").last.map(String.init)
    return lastLine ?? "exit code \(p.terminationStatus)"
}

private func freeBytes() -> Int64 {
    let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage ?? 0
}

private func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Finds node_modules and Rust target/ folders under the project roots, without descending into them.
private func findProjectBuildFolders() -> [Target] {
    var found: [Target] = []
    let fm = FileManager.default
    for root in projectRoots where fm.fileExists(atPath: root.path) {
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if walker.level > 6 { walker.skipDescendants(); continue }
            let name = url.lastPathComponent
            let parent = url.deletingLastPathComponent()
            let isNode = name == "node_modules"
            let isRust = name == "target" && fm.fileExists(atPath: parent.appendingPathComponent("Cargo.toml").path)
            let isDerived = name == "DerivedData"
            guard isNode || isRust || isDerived else { continue }
            walker.skipDescendants()
            let project = parent.path.replacingOccurrences(of: home.path, with: "~")
            found.append(Target(
                id: url.path, name: "\(name) in \(project)",
                note: isNode ? "Reinstall with npm/yarn install." : "Rebuilt on the next build.",
                paths: [url], safety: .safe, action: .deleteFolders))
        }
    }
    return found
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var targets: [Target] = []
    @Published var projects: [Target] = []
    @Published var free: Int64 = freeBytes()
    @Published var scanning = false
    @Published var busy: Set<String> = []
    @Published var lastMessage: String?

    var reclaimable: Int64 {
        (targets + projects).filter { $0.safety == .safe }.compactMap(\.bytes).reduce(0, +)
    }

    init() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.free = freeBytes() }
        }
        scan()
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        free = freeBytes()
        targets = knownTargets()
        projects = []
        Task.detached(priority: .utility) {
            let base = knownTargets()
            for t in base {
                let size = diskUsage(t.paths)
                await MainActor.run { self.setSize(t.id, size) }
            }
            let found = findProjectBuildFolders()
            await MainActor.run { self.projects = found }
            for t in found {
                let size = diskUsage(t.paths)
                await MainActor.run { self.setSize(t.id, size) }
            }
            await MainActor.run {
                self.projects.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
                self.projects.removeAll { ($0.bytes ?? 0) < 50_000_000 } // hide small ones
                self.scanning = false
            }
        }
    }

    private func setSize(_ id: String, _ size: Int64) {
        if let i = targets.firstIndex(where: { $0.id == id }) { targets[i].bytes = size }
        if let i = projects.firstIndex(where: { $0.id == id }) { projects[i].bytes = size }
    }

    func clean(_ t: Target) {
        busy.insert(t.id)
        let before = freeBytes()
        Task.detached(priority: .userInitiated) {
            let error = Self.perform(t)
            let size = diskUsage(t.paths)
            let after = freeBytes()
            await MainActor.run {
                self.busy.remove(t.id)
                self.setSize(t.id, size)
                self.free = after
                self.lastMessage = error.map { "\(t.name) failed: \($0)" }
                    ?? "\(t.name): freed \(fmt(max(0, after - before)))"
            }
        }
    }

    /// Returns an error message if the clean failed.
    nonisolated private static func perform(_ t: Target) -> String? {
        let fm = FileManager.default
        switch t.action {
        case .emptyFolders:
            for dir in t.paths {
                for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                    removeForcefully(item)
                }
            }
        case .deleteFolders:
            t.paths.forEach(removeForcefully)
        case .command(let cmd):
            return shell(cmd)
        case .reveal:
            break
        }
        return nil
    }

    /// Go's module cache is read-only, so fall back to `rm -rf` after making it writable.
    nonisolated private static func removeForcefully(_ url: URL) {
        if (try? FileManager.default.removeItem(at: url)) != nil { return }
        run("/bin/chmod", ["-R", "u+w", url.path])
        run("/bin/rm", ["-rf", url.path])
    }

    func reveal(_ t: Target) {
        let existing = t.paths.filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(existing.isEmpty ? t.paths : existing)
    }

    func openStorageSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)
    }
}

// MARK: - Views

struct Row: View {
    let target: Target
    @ObservedObject var store: Store
    @State private var confirming = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.name).font(.body).lineLimit(1).truncationMode(.middle)
                    Text(target.safety.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(target.safety.color)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(target.safety.color.opacity(0.15), in: Capsule())
                }
                Text(target.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Group {
                if let b = target.bytes { Text(fmt(b)).monospacedDigit() } else { ProgressView().controlSize(.small) }
            }
            .frame(width: 70, alignment: .trailing)
            button.frame(width: 78)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { Button("Show in Finder") { store.reveal(target) } }
    }

    @ViewBuilder private var button: some View {
        if store.busy.contains(target.id) {
            ProgressView().controlSize(.small)
        } else if case .reveal = target.action {
            Button("Show") { store.reveal(target) }
        } else if confirming {
            Button("Sure?") { confirming = false; store.clean(target) }
                .tint(.red).buttonStyle(.borderedProminent)
        } else {
            Button("Clean") {
                confirming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { confirming = false }
            }
            .disabled((target.bytes ?? 0) == 0)
        }
    }
}

struct Panel: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(fmt(store.free)) free").font(.title2.weight(.semibold))
                    Text("About \(fmt(store.reclaimable)) can be cleared safely")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
                Button { store.scan() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Scan again").disabled(store.scanning)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Caches and build output", store.targets.filter { $0.safety != .keep }
                        .sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) })
                    if !store.projects.isEmpty {
                        section("Project build folders", store.projects)
                    }
                    section("Big, but yours to decide", store.targets.filter { $0.safety == .keep }
                        .sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) })
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 440)

            Divider()

            HStack {
                Text(store.lastMessage ?? "Click Clean twice to confirm.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Storage Settings…") { store.openStorageSettings() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
            .padding(10)
        }
        .frame(width: 520)
    }

    @ViewBuilder private func section(_ title: String, _ items: [Target]) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 12).padding(.bottom, 4)
        ForEach(items) { t in
            Row(target: t, store: store)
            Divider()
        }
    }
}

@main
struct SweepApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            Image(systemName: "internaldrive")
        }
        .menuBarExtraStyle(.window)
    }
}
