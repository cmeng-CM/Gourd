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

import Sparkle

/// Sparkle updater delegate for 壶中天 / Gourd.
///
/// Upstream returned the appcast URL of the selected update channel, and every
/// channel pointed at an Atoll-hosted feed. This fork publishes no appcast of
/// its own, so no feed URL is provided at all: with no feed to resolve, Sparkle
/// cannot contact an upstream (or any other) update endpoint at runtime.
class AtollUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        return nil
    }
}
