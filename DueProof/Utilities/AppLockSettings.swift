import Foundation

enum AppLockSettings {
    static let isEnabledKey = DueProofPrivacySettings.appLockEnabledKey
    static var defaults: UserDefaults { DueProofPrivacySettings.defaults }

    static func migrateLegacyStandardDefaultIfNeeded() {
        guard defaults.object(forKey: isEnabledKey) == nil,
              UserDefaults.standard.object(forKey: isEnabledKey) != nil
        else {
            return
        }

        defaults.set(UserDefaults.standard.bool(forKey: isEnabledKey), forKey: isEnabledKey)
    }
}
