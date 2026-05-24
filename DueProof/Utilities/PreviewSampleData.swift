import Foundation
import SwiftData

@MainActor
enum PreviewSampleData {
    static func container() -> ModelContainer {
        let schema = Schema([Claim.self, ProofItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        sampleClaims.forEach { context.insert($0) }
        return container
    }

    static var sampleClaims: [Claim] {
        [
            Claim(
                title: "Nike shoes return",
                category: .returnItem,
                merchant: "Nike",
                valueAtRisk: 140,
                deadline: DateHelpers.calendar.date(byAdding: .day, value: 5, to: Date()),
                reminderDate: DateHelpers.calendar.date(byAdding: .day, value: 3, to: Date()),
                notes: "Keep the receipt and shipping label together."
            ),
            Claim(
                title: "Target gift card",
                category: .giftCard,
                merchant: "Target",
                valueAtRisk: 38.50,
                deadline: nil,
                reminderDate: DateHelpers.calendar.date(byAdding: .day, value: 30, to: Date())
            ),
            Claim(
                title: "FSA dental reimbursement",
                category: .reimbursement,
                merchant: "FSA",
                valueAtRisk: 220,
                deadline: DateHelpers.calendar.date(byAdding: .day, value: 20, to: Date())
            ),
            Claim(
                title: "MacBook warranty",
                category: .warranty,
                merchant: "Apple",
                valueAtRisk: 0,
                deadline: DateHelpers.calendar.date(byAdding: .day, value: 200, to: Date())
            ),
            Claim(
                title: "Streaming trial cancellation",
                category: .subscription,
                merchant: "Streamly",
                valueAtRisk: 14.99,
                deadline: DateHelpers.calendar.date(byAdding: .day, value: 1, to: Date()),
                reminderDate: DateHelpers.calendar.date(byAdding: .hour, value: 12, to: Date())
            )
        ]
    }
}
