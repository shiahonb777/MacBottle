//
//  GameDetailSheet.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WhiskyKit

/// Detail sheet shown when the user clicks a Library card.
///
/// Presents recipe metadata, install/play state, and drives the
/// `GameInstaller` flow for Steam/GOG/custom recipes.
struct GameDetailSheet: View { // swiftlint:disable:this type_body_length
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bottleVM: BottleVM

    @StateObject private var installer: GameInstaller
    @State private var installedGame: InstalledGame?
    @State private var showUninstallConfirm = false

    init(recipe: Recipe) {
        self.recipe = recipe
        _installer = StateObject(wrappedValue: GameInstaller(recipe: recipe))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataGrid
                    if let notes = recipe.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.headline)
                            Text(verbatim: notes)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    phaseSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 580, minHeight: 520)
        .onAppear { refreshInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: .macbottleInstalledGamesChanged)) { _ in
            refreshInstalled()
        }
        .confirmationDialog(
            "Remove \(recipe.title) from your library?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "The bottle and its files are kept on disk. Only the MacBottle record is removed.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            CachedAsyncImage(
                url: recipe.iconURL,
                success: { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                },
                placeholder: {
                    ZStack { Rectangle().fill(.quaternary); ProgressView().controlSize(.small) }
                },
                failure: {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "gamecontroller").font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .frame(width: 172, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: recipe.title)
                    .font(.title2.weight(.semibold))
                Text(verbatim: recipe.id)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(20)
    }

    private var metadataGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            metadataRow("Compatibility", value: recipe.compatibility.rawValue.capitalized, tint: tintColor)
            metadataRow("Renderer", value: recipe.renderer.rawValue)
            metadataRow("DirectX", value: recipe.dxVersion.rawValue.uppercased())
            metadataRow("Minimum macOS", value: recipe.minMacOS)
            if let installerKind = recipe.installer {
                metadataRow("Installer", value: installerKind.rawValue.capitalized)
            }
            if !recipe.winetricks.isEmpty {
                metadataRow(
                    "Winetricks",
                    value: recipe.winetricks.joined(separator: ", "),
                    monospaced: true
                )
            }
            if !recipe.env.isEmpty {
                metadataRow("Environment", value: "\(recipe.env.count) variable(s)")
            }
        }
    }

    @ViewBuilder
    private func metadataRow(
        _ label: String, value: String, tint: Color? = nil, monospaced: Bool = false
    ) -> some View {
        GridRow {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(verbatim: value)
                .foregroundStyle(tint ?? .primary)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
    }

    private var tintColor: Color {
        switch recipe.compatibility {
        case .platinum: return .blue
        case .gold:     return .yellow
        case .silver:   return .gray
        case .bronze:   return .orange
        case .broken:   return .red
        }
    }

    @ViewBuilder
    private var phaseSection: some View {
        switch installer.phase {
        case .idle:
            EmptyView()
        case .creatingBottle:
            phaseRow(systemImage: "hourglass", text: "Creating bottle…")
        case .downloadingSteamSetup:
            phaseRow(systemImage: "arrow.down.circle", text: "Downloading SteamSetup.exe…")
        case .runningInstaller:
            phaseRow(
                systemImage: "gearshape.2",
                // swiftlint:disable:next line_length
                text: "Installer is running. Complete the installation in the window that just opened, then come back here."
            )
        case .awaitingMainExe:
            VStack(alignment: .leading, spacing: 8) {
                phaseRow(systemImage: "checkmark.seal", text: "Installer finished. Pick the main game executable.")
                Button("Locate main .exe") {
                    pickMainExe()
                }
                .buttonStyle(.bordered)
            }
        case .done:
            phaseRow(systemImage: "checkmark.circle.fill", text: "Installed. You can launch it anytime.", tint: .green)
        case .failed(let message):
            phaseRow(systemImage: "exclamationmark.triangle.fill", text: message, tint: .orange)
        }
    }

    @ViewBuilder
    private func phaseRow(systemImage: String, text: String, tint: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)

            if installedGame != nil {
                Button("Uninstall", role: .destructive) { showUninstallConfirm = true }
                    .buttonStyle(.bordered)
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    installer.begin()
                } label: {
                    Label(installButtonLabel, systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                .disabled(installer.phase != .idle && !isTerminal)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var isTerminal: Bool {
        switch installer.phase {
        case .done, .failed, .idle: return true
        default: return false
        }
    }

    private var installButtonLabel: String {
        switch recipe.installer {
        case .steam: return "Install via Steam"
        case .gog: return "Install from GOG installer"
        case .custom: return "Install from .exe"
        case .none: return "Install"
        }
    }

    // MARK: - Actions

    private func refreshInstalled() {
        installedGame = InstalledGameRegistry.shared.game(forRecipe: recipe.id)
    }

    private func uninstall() {
        try? InstalledGameRegistry.shared.remove(recipeID: recipe.id)
        installedGame = nil
        NotificationCenter.default.post(name: .macbottleInstalledGamesChanged, object: nil)
    }

    private func play() {
        guard let installed = installedGame,
              let bottle = bottleVM.bottles.first(where: { $0.url == installed.bottleURL }) else {
            installer.phase = .failed(message: "Backing bottle no longer exists.")
            return
        }
        if let winPath = installed.mainExe, let exeURL = resolveMacURL(forWinPath: winPath, bottle: bottle) {
            Task.detached(priority: .userInitiated) {
                try? await Wine.runProgram(at: exeURL, bottle: bottle)
            }
        } else {
            installer.phase = .failed(message: "Main executable path is invalid.")
        }
    }

    private func pickMainExe() {
        guard let bottleURL = installer.bottleURL,
              let bottle = bottleVM.bottles.first(where: { $0.url == bottleURL }) else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.exe]
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.prompt = "Select"
        panel.message = "Choose the main game executable"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            installer.registerMainExecutable(url, bottle: bottle)
        }
    }

    private func resolveMacURL(forWinPath winPath: String, bottle: Bottle) -> URL? {
        guard winPath.hasPrefix("C:") else {
            return URL(fileURLWithPath: winPath)
        }
        let relative = String(winPath.dropFirst(2))
            .replacingOccurrences(of: "\\", with: "/")
        return bottle.url.appending(path: "drive_c").appending(path: relative)
    }
}
