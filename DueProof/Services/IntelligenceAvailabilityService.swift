import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum IntelligenceAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .available:
            return "Smart suggestions can use Apple's on-device intelligence on this device."
        case .unavailable:
            return "Smart suggestions are limited on this device. You can still add claims manually."
        }
    }
}

final class IntelligenceAvailabilityService {
    static let shared = IntelligenceAvailabilityService()

    private init() {}

    func availability() -> IntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable(reason: displayName(for: reason))
            }
        }
        #endif

        return .unavailable(reason: "Apple on-device intelligence is not available.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func displayName(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled."
        case .deviceNotEligible:
            return "This device is not eligible for Apple Intelligence."
        case .modelNotReady:
            return "The on-device model is not ready."
        @unknown default:
            return "Apple on-device intelligence is unavailable."
        }
    }
    #endif
}
