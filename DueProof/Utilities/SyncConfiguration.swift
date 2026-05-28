import Foundation

enum SyncConfiguration {
    static let iCloudSyncEnabledKey = "DueProof.iCloudSyncEnabled"
    static let iCloudSyncRequiresRestartKey = "DueProof.iCloudSyncRequiresRestart"

    static var isICloudSyncEnabled: Bool {
        isICloudSyncEnabled(defaults: .standard)
    }

    static var iCloudSyncRequiresRestart: Bool {
        UserDefaults.standard.bool(forKey: iCloudSyncRequiresRestartKey)
    }

    static func isICloudSyncEnabled(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: iCloudSyncEnabledKey)
    }

    static func setICloudSyncEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        let previousValue = isICloudSyncEnabled(defaults: defaults)
        defaults.set(isEnabled, forKey: iCloudSyncEnabledKey)
        if previousValue != isEnabled {
            defaults.set(true, forKey: iCloudSyncRequiresRestartKey)
        }
    }

    static func markLaunchConfigurationApplied(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: iCloudSyncRequiresRestartKey)
    }
}
