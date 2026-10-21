/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import Cocoa

final class NormalStatusIcon: HelperstatusIcon {
    init(isControl: Bool) { super.init(role: isControl ? .control : .divider) }
}
