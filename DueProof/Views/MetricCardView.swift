import SwiftUI

struct MetricCardView: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: AppTheme.minimumTapTarget)
        .padding(16)
        .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

#Preview {
    HStack {
        MetricCardView(title: "Urgent", value: "3", systemImage: "exclamationmark.circle.fill", tint: .orange)
        MetricCardView(title: "Recovered", value: "$428", systemImage: "checkmark.circle.fill", tint: .green)
    }
    .padding()
}
