import SwiftUI

struct ClaimRowView: View {
    let claim: Claim

    var body: some View {
        ClaimCardView(claim: claim, style: .row)
    }
}

struct StatusPillView: View {
    let status: ClaimStatus

    var body: some View {
        Label(status.displayName, systemImage: status.symbolName)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(status.tintColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tintColor.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .accessibilityLabel("Status \(status.displayName)")
    }
}

#Preview {
    ClaimRowView(claim: PreviewSampleData.sampleClaims[0])
        .padding()
}
