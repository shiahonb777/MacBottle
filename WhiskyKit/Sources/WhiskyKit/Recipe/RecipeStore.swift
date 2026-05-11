//
//  RecipeStore.swift
//  WhiskyKit
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

import Foundation
import os.log

/// Loads recipes that ship with the app bundle.
///
/// Recipes live in the WhiskyKit package as JSON resources under
/// `Recipes/<platform>/<id>.json`. At build time they are copied into the
/// bundle by SwiftPM's resource processing. At runtime we walk the bundle's
/// `Recipes` directory and decode every `.json` file we find.
///
/// The loader is intentionally strict: a malformed recipe is logged and
/// skipped, but never silently accepted with incomplete data. CI catches
/// malformed recipes in PR review; this runtime check is a second line of
/// defense for end users.
///
/// Results are cached in memory on first access because recipes ship with
/// the app and never change at runtime. The cache is per-`RecipeStore`
/// instance to keep tests hermetic.
public final class RecipeStore: @unchecked Sendable {
    /// The process-wide store, bound to `WhiskyKit`'s resource bundle.
    /// Tests should construct their own `RecipeStore(bundle:)` for hermetic
    /// fixtures instead of mutating this instance.
    public static let shared = RecipeStore(bundle: .module)

    private let bundle: Bundle
    private let lock = NSLock()
    private var cache: [String: Recipe]?

    /// Construct a store backed by a specific bundle.
    ///
    /// `Bundle.module` is internal to the package, so callers outside
    /// `WhiskyKit` (the app target, tests) must pass `.module` from within
    /// their own module or use `RecipeStore.shared`.
    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    /// Returns every recipe shipped with the current build, keyed by `id`.
    ///
    /// Missing `Recipes/` directory is treated as "no recipes shipped" and
    /// returns an empty dictionary rather than throwing. This keeps the
    /// app usable even if the package resources have not been processed yet
    /// (e.g. fresh checkout before first build).
    public func loadAll() -> [String: Recipe] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache { return cached }
        let fresh = Self.scan(bundle: bundle)
        cache = fresh
        return fresh
    }

    /// Drop the in-memory cache. Intended for tests only; the shipped app
    /// has no reason to invalidate because resources are read-only.
    public func invalidateCache() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    private static func scan(bundle: Bundle) -> [String: Recipe] {
        guard let rootURL = bundle.url(forResource: "Recipes", withExtension: nil) else {
            Logger.wineKit.info("MacBottle: no Recipes directory in bundle; shipping empty recipe set")
            return [:]
        }

        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var result: [String: Recipe] = [:]
        let decoder = JSONDecoder()

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "json" else { continue }
            do {
                let data = try Data(contentsOf: url)
                let recipe = try decoder.decode(Recipe.self, from: data)
                if let existing = result[recipe.id] {
                    Logger.wineKit.error(
                        // swiftlint:disable:next line_length
                        "MacBottle: duplicate recipe id \(recipe.id), keeping \(existing.title), skipping \(recipe.title)"
                    )
                    continue
                }
                result[recipe.id] = recipe
            } catch {
                Logger.wineKit.error(
                    "MacBottle: failed to decode recipe at \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        Logger.wineKit.info("MacBottle: loaded \(result.count) recipe(s) from bundle")
        return result
    }

    /// Look up a single recipe by its stable id.
    public func recipe(id: String) -> Recipe? {
        loadAll()[id]
    }
}
