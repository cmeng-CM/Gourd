/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// Runtime context flags used to keep the app's launch deterministic on CI.
enum AppRuntimeEnvironment {
    /// `true` only in DEBUG builds launched by XCUITest (`--uitesting`); always false in Release.
    static let isUITesting: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--uitesting")
        #else
        return false
        #endif
    }()

    /// `true` whenever this process is a test host — the unit-test host included
    /// (XCTest injects `XCTestConfigurationFilePath` and loads `XCTestCase` into the
    /// app process). Modified for Gourd (2026-09-28): the permission-request paths
    /// check this so a `xcodebuild test` run never raises a system consent prompt
    /// and never leaves a TCC entry behind for the Debug bundle id.
    static let isRunningTests: Bool = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }()
}
