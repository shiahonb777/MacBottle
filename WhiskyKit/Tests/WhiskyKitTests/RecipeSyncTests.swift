//
//  RecipeSyncTests.swift
//  WhiskyKitTests
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

import XCTest
@testable import WhiskyKit

final class RecipeSyncTests: XCTestCase {

    // MARK: - Diff

    func testDiffFirstSyncTreatsEverythingAsAdded() {
        let remote = RecipeIndex(
            generatedAt: "2026-05-12T00:00:00Z",
            recipes: [
                .init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10),
                .init(id: "steam.2", path: "steam/2.json", sha: "b", size: 20)
            ]
        )
        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: nil, knownRecipes: [:]
        )
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.allSatisfy { $0.kind == .added })
        XCTAssertEqual(changes.map(\.id), ["steam.1", "steam.2"])
    }

    func testDiffDetectsAddedRemovedAndUpdated() {
        let remote = RecipeIndex(
            generatedAt: "2026-05-12T00:00:00Z",
            recipes: [
                .init(id: "steam.1", path: "steam/1.json", sha: "a-new", size: 10),
                .init(id: "steam.3", path: "steam/3.json", sha: "c", size: 30)
            ]
        )
        let local: [RecipeIndex.Entry] = [
            .init(id: "steam.1", path: "steam/1.json", sha: "a-old", size: 10),
            .init(id: "steam.2", path: "steam/2.json", sha: "b", size: 20)
        ]

        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: local, knownRecipes: [:]
        )

        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes[0].kind, .added)    // steam.3
        XCTAssertEqual(changes[0].id, "steam.3")
        XCTAssertEqual(changes[1].kind, .updated)  // steam.1 sha changed
        XCTAssertEqual(changes[1].id, "steam.1")
        XCTAssertEqual(changes[2].kind, .removed)  // steam.2 gone remotely
        XCTAssertEqual(changes[2].id, "steam.2")
    }

    func testDiffIsEmptyWhenNothingChanged() {
        let entries: [RecipeIndex.Entry] = [
            .init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)
        ]
        let remote = RecipeIndex(generatedAt: "now", recipes: entries)

        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: entries, knownRecipes: [:]
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testDiffEnrichesChangesWithKnownRecipeMetadata() {
        let remote = RecipeIndex(
            generatedAt: "now",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
        )
        let known: Recipe = Recipe(
            id: "steam.1", title: "Terraria",
            iconURL: URL(string: "https://example.com/t.jpg"),
            dxVersion: .d3d9, minMacOS: "14.0",
            renderer: .wined3d, compatibility: .platinum
        )
        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: nil, knownRecipes: ["steam.1": known]
        )
        XCTAssertEqual(changes.first?.title, "Terraria")
        XCTAssertEqual(changes.first?.iconURL?.host, "example.com")
    }

    // MARK: - Cache

    func testCacheRoundTripsRecipes() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = RecipeCache(root: temp)
        let recipe = Recipe(
            id: "steam.9999", title: "TestGame",
            dxVersion: .d3d11, minMacOS: "14.0",
            renderer: .d3dmetal, compatibility: .gold
        )
        try cache.storeRecipe(recipe)

        XCTAssertEqual(cache.loadRecipe(id: "steam.9999")?.title, "TestGame")
        XCTAssertEqual(cache.loadAll().count, 1)

        try cache.removeRecipe(id: "steam.9999")
        XCTAssertNil(cache.loadRecipe(id: "steam.9999"))
        XCTAssertTrue(cache.loadAll().isEmpty)
    }

    func testCacheMetaPersistsAcrossInstances() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache1 = RecipeCache(root: temp)
        let meta = RecipeCache.Meta(
            etag: "W/\"abc\"",
            index: RecipeIndex(
                generatedAt: "2026-05-12T00:00:00Z",
                recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
            ),
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try cache1.saveMeta(meta)

        // A fresh cache instance pointed at the same root must see the
        // same meta. This is the persistence guarantee the sync engine
        // depends on across app launches.
        let cache2 = RecipeCache(root: temp)
        let loaded = cache2.loadMeta()
        XCTAssertEqual(loaded.etag, "W/\"abc\"")
        XCTAssertEqual(loaded.index?.recipes.count, 1)
        XCTAssertEqual(loaded.lastSyncAt, meta.lastSyncAt)
    }

    // MARK: - Source with stub fetcher

    func testSourceDecodesIndexFromFetcher() async throws {
        let index = RecipeIndex(
            generatedAt: "now",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
        )
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder().encode(index)

        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { _, _ in (data, "W/\"v1\"") }
        )
        let (fetched, etag) = try await source.fetchIndex(previousETag: nil)
        XCTAssertEqual(fetched.recipes.count, 1)
        XCTAssertEqual(etag, "W/\"v1\"")
    }

    func testSourceSurfacesNotModified() async {
        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { _, _ in throw RemoteRecipeError.notModified }
        )
        do {
            _ = try await source.fetchIndex(previousETag: "W/\"v1\"")
            XCTFail("expected notModified")
        } catch RemoteRecipeError.notModified {
            // pass
        } catch {
            XCTFail("got unexpected error: \(error)")
        }
    }

    // MARK: - Service end-to-end with stubs

    func testServiceAppliesAddAndRemoveAtomically() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-svc-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = seedCacheWithStaleEntry(at: temp)
        let (indexData, recipeData) = buildRemoteFixtures()
        let source = stubSource(indexData: indexData, recipeData: recipeData)

        let service = RecipeSyncService(source: source, cache: cache)
        let check = try await service.check(knownRecipes: [:])
        XCTAssertEqual(check.changes.count, 2)

        let outcomes = try await service.apply(
            changes: check.changes,
            remoteIndex: check.remoteIndex,
            newETag: check.newETag
        )
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertTrue(outcomes.allSatisfy(\.success))

        XCTAssertNotNil(cache.loadRecipe(id: "steam.1"))
        XCTAssertNil(cache.loadRecipe(id: "steam.2"))
        let meta = cache.loadMeta()
        XCTAssertEqual(meta.etag, "W/\"new\"")
        XCTAssertEqual(meta.index?.recipes.map(\.id), ["steam.1"])
    }

    // MARK: Fixture helpers

    private func seedCacheWithStaleEntry(at root: URL) -> RecipeCache {
        let cache = RecipeCache(root: root)
        let stale = Recipe(
            id: "steam.2", title: "Stale",
            dxVersion: .d3d11, minMacOS: "14.0",
            renderer: .d3dmetal, compatibility: .gold
        )
        // swiftlint:disable:next force_try
        try! cache.storeRecipe(stale)
        // swiftlint:disable:next force_try
        try! cache.saveMeta(.init(
            etag: "W/\"old\"",
            index: RecipeIndex(
                generatedAt: "old",
                recipes: [.init(id: "steam.2", path: "steam/2.json", sha: "s1", size: 10)]
            ),
            lastSyncAt: Date.distantPast
        ))
        return cache
    }

    private func buildRemoteFixtures() -> (indexData: Data, recipeData: Data) {
        let newIndex = RecipeIndex(
            generatedAt: "new",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "n1", size: 20)]
        )
        let newRecipe = Recipe(
            id: "steam.1", title: "Fresh",
            dxVersion: .d3d11, minMacOS: "14.0",
            renderer: .d3dmetal, compatibility: .gold
        )
        // swiftlint:disable force_try
        return (try! JSONEncoder().encode(newIndex),
                try! JSONEncoder().encode(newRecipe))
        // swiftlint:enable force_try
    }

    private func stubSource(indexData: Data, recipeData: Data) -> RemoteRecipeSource {
        RemoteRecipeSource(
            configuration: .init(),
            fetcher: { url, _ in
                if url.lastPathComponent == "_index.json" {
                    return (indexData, "W/\"new\"")
                }
                return (recipeData, nil)
            }
        )
    }
}
