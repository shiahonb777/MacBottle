//
//  RecipeSyncService.swift
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

/// Coordinator that owns the full sync lifecycle:
///
/// 1. Check the upstream repo for a fresh index (conditional GET).
/// 2. Diff the new index against whatever we last accepted.
/// 3. Hand the diff to the UI for user confirmation.
/// 4. Apply the user's selections by downloading additions/updates and
///    deleting removals, updating the on-disk cache atomically.
///
/// Network and disk are abstracted via `RemoteRecipeSource` and
/// `RecipeCache`. Nothing in this class blocks the main thread; all
/// methods are `async`.
public final class RecipeSyncService: @unchecked Sendable {
    public struct CheckResult: Sendable {
        /// New remote index (either freshly fetched or the cached one
        /// from a prior run if nothing changed).
        public let remoteIndex: RecipeIndex
        /// ETag to store back with the cache if we fetched a fresh one.
        /// `nil` when the server responded 304 and we kept the cached index.
        public let newETag: String?
        /// Changes the user can choose from. Empty means "nothing to do".
        public let changes: [RecipeChange]
    }

    public let source: RemoteRecipeSource
    public let cache: RecipeCache

    public init(
        source: RemoteRecipeSource = RemoteRecipeSource(),
        cache: RecipeCache = .default
    ) {
        self.source = source
        self.cache = cache
    }

    // MARK: - Check

    /// Fetch the remote index and compute the diff vs the cached snapshot.
    /// Never throws for "nothing changed" — that case returns a
    /// `CheckResult` with an empty `changes` array.
    public func check(knownRecipes: [String: Recipe]) async throws -> CheckResult {
        let meta = cache.loadMeta()

        let remoteIndex: RecipeIndex
        let newETag: String?
        do {
            let fetched = try await source.fetchIndex(previousETag: meta.etag)
            remoteIndex = fetched.0
            newETag = fetched.1
        } catch RemoteRecipeError.notModified {
            // Nothing changed since last check. Surface that as "no diff"
            // rather than an error the UI has to special-case.
            guard let cachedIndex = meta.index else {
                // Shouldn't really happen: server says "not modified" but
                // we don't have the previous state. Fall through to a
                // follow-up unconditional fetch to self-heal.
                let (index, etag) = try await source.fetchIndex(previousETag: nil)
                let changes = RecipeSyncDiff.compute(
                    remoteIndex: index,
                    localEntries: nil,
                    knownRecipes: knownRecipes
                )
                return CheckResult(remoteIndex: index, newETag: etag, changes: changes)
            }
            return CheckResult(remoteIndex: cachedIndex, newETag: nil, changes: [])
        }

        let changes = RecipeSyncDiff.compute(
            remoteIndex: remoteIndex,
            localEntries: meta.index?.recipes,
            knownRecipes: knownRecipes
        )
        return CheckResult(remoteIndex: remoteIndex, newETag: newETag, changes: changes)
    }

    // MARK: - Apply

    /// Apply a subset of the changes returned by `check`.
    ///
    /// The service fetches files for `added` and `updated` changes,
    /// deletes cached files for `removed` changes, and writes a fresh
    /// `meta.json` reflecting the post-apply state so subsequent checks
    /// produce the correct diff.
    ///
    /// Accepts changes in any order. Partial failures are surfaced as
    /// per-change results; the overall call does not throw unless the
    /// meta write fails.
    public struct ApplyOutcome: Sendable {
        public let change: RecipeChange
        public let success: Bool
        public let error: Error?
    }

    public func apply(
        changes accepted: [RecipeChange],
        remoteIndex: RecipeIndex,
        newETag: String?
    ) async throws -> [ApplyOutcome] {
        var outcomes: [ApplyOutcome] = []

        for change in accepted {
            do {
                switch change.kind {
                case .added, .updated:
                    guard let entry = change.remoteEntry else {
                        throw RemoteRecipeError.recipeUnreachable(
                            id: change.id,
                            underlying: NSError(
                                domain: "RecipeSyncService", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Missing remote entry"]
                            )
                        )
                    }
                    let recipe = try await source.fetchRecipe(entry)
                    try cache.storeRecipe(recipe)
                case .removed:
                    try cache.removeRecipe(id: change.id)
                }
                outcomes.append(ApplyOutcome(change: change, success: true, error: nil))
            } catch {
                Logger.wineKit.error(
                    "MacBottle: failed to apply \(change.kind.rawValue) \(change.id): \(error.localizedDescription)"
                )
                outcomes.append(ApplyOutcome(change: change, success: false, error: error))
            }
        }

        // Only update meta when at least one change succeeded. We do not
        // mark the new index as accepted until it is actually reflected
        // in the cache, so a fully-failed apply leaves the client in the
        // same state it started in and will re-prompt next time.
        if outcomes.contains(where: { $0.success }) {
            var meta = cache.loadMeta()
            // The accepted index is "what the user said yes to" which
            // may be the full remote index or a subset. The simplest
            // robust behaviour is to record the full remote index as the
            // baseline once any change is applied — rejected changes
            // will still show up next time as a diff if the user reopens
            // the sync sheet, because we don't have a concept of
            // "rejected" (and don't want one: users can change their mind).
            meta.index = remoteIndex
            if let newETag { meta.etag = newETag }
            meta.lastSyncAt = Date()
            try cache.saveMeta(meta)
        }

        return outcomes
    }
}
