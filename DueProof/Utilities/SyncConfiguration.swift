import Foundation

enum SyncConfiguration {
    static let iCloudSyncEnabledKey = "DueProof.iCloudSyncEnabled"
    static let iCloudSyncRequiresRestartKey = "DueProof.iCloudSyncRequiresRestart"

    static var isICloudSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
    }
}
