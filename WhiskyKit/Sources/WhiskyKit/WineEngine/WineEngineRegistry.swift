//
//  WineEngineRegistry.swift
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

/// Process-wide holder of the currently active `WineEngine`.
///
/// There is exactly one engine selected at any time because a Wine
/// environment is not cheap to swap — every bottle is implicitly bound to
/// the engine that created it. Switching engines for real is a v0.4+
/// feature. For now, the registry exists so every caller reads the engine
/// through a single symbol, and the day we actually support multiple
/// engines, only the registry needs to grow a setter.
public final class WineEngineRegistry: @unchecked Sendable {
    public static let shared = WineEngineRegistry()

    private let lock = NSLock()
    private var _current: any WineEngine

    /// The default engine for v0.1: CrossOver-derived Wine inherited from
    /// Whisky. This will become user-configurable in v0.4 when the
    /// abstraction has a second concrete implementation to switch between.
    public init(current: any WineEngine = CrossOverEngine.default) {
        self._current = current
    }

    /// The engine the rest of MacBottle should route through.
    public var current: any WineEngine {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    /// Replace the active engine. Intended for v0.4 engine switching and
    /// for tests that need to swap in a fake engine pointing at a temp
    /// directory. Callers on the main flow should prefer reading `current`.
    public func setCurrent(_ engine: any WineEngine) {
        lock.lock()
        _current = engine
        lock.unlock()
    }
}
