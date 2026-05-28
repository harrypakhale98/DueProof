import SwiftUI
import WidgetKit

struct DueProofWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedClaimSnapshot
}

struct DueProofWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueProofWidgetEntry {
        DueProofWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DueProofWidgetEntry) -> Void) {
        completion(DueProofWidgetEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueProofWidgetEntry>) -> Void) {
        let entry = DueProofWidgetEntry(date: Date(), snapshot: loadSnapshot())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadSnapshot() -> SharedClaimSnapshot {
        guard !DueProofPrivacySettings.isAppLockEnabled else {
            return .empty
        }

        return SharedClaimSnapshotStore.shared.load() ?? .empty
    }
}

struct DueProofWidget: Widget {
    let kind = "DueProofWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DueProofWidgetProvider()) { entry in
            DueProofWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("DueProof")
        .description("See the claims that need attention.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct DueProofWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueProofWidgetEntry

    var body: some View {
        if DueProofPrivacySettings.isAppLockEnabled {
            lockedView
                .widgetURL(URL(string: "dueproof://"))
        } else {
            unlockedView
        }
    }

    @ViewBuilder
    private var unlockedView: some View {
        switch family {
        case .systemMedium:
            mediumView
                .widgetURL(URL(string: "dueproof://search?q=urgent"))
        case .accessoryRectangular:
            accessoryView
                .widgetURL(URL(string: "dueproof://search?q=urgent"))
        default:
            smallView
                .widgetURL(URL(string: "dueproof://search?q=urgent"))
        }
    }

    private var lockedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.teal)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text("DueProof Locked")
                .font(family == .accessoryRectangular ? .caption.weight(.semibold) : .headline)
                .lineLimit(2)

            if family != .accessoryRectangular {
                Text("Open DueProof to view private claims.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DueProof locked. Open DueProof to view private claims.")
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("DueProof", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.teal)

            Spacer(minLength: 0)

            Text(currency(entry.snapshot.moneyAtRisk))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("at risk")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                StatusPill(value: entry.snapshot.urgentCount, label: "Urgent", color: .orange)
                StatusPill(value: entry.snapshot.overdueCount, label: "Late", color: .red)
            }
        }
        .padding()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DueProof", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.teal)
                Spacer()
                Text(entry.snapshot.generatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency(entry.snapshot.moneyAtRisk))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("at risk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Metric(value: entry.snapshot.urgentCount, label: "Urgent", color: .orange)
                Metric(value: entry.snapshot.overdueCount, label: "Late", color: .red)
                Metric(value: entry.snapshot.prooflessOpenCount, label: "No proof", color: .secondary)
            }

            Divider()

            if let nextAction = entry.snapshot.nextAction,
               let url = URL(string: "dueproof://claim/\(nextAction.id.uuidString)") {
                Link(destination: url) {
                    HStack(spacing: 10) {
                        Image(systemName: nextAction.categoryIconName)
                            .foregroundStyle(.teal)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(nextAction.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(nextAction.urgencyLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                }
            } else {
                Label("No open claims", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var accessoryView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("DueProof")
                    .font(.caption.weight(.semibold))
                Text("\(entry.snapshot.urgentCount) urgent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(currency(entry.snapshot.moneyAtRisk))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func currency(_ value: Double) -> String {
        SharedClaimSnapshot.nonNegativeFinite(value)
            .formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

private struct Metric: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 46)
    }
}

private struct StatusPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(value)")
                .monospacedDigit()
            Text(label)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

#Preview(as: .systemMedium) {
    DueProofWidget()
} timeline: {
    DueProofWidgetEntry(date: Date(), snapshot: .empty)
}
