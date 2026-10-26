import SwiftUI

/// M1 shell. The real onboarding and workspace replace this view in M2.
struct PromethRootView: View {
    var body: some View {
        ZStack {
            Color(hex: PromethDesign.readingSurfaceLight)
            VStack(spacing: 12) {
                Brand()
                Text("Private · On this Mac")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            minWidth: PromethDesign.windowMinWidth,
            minHeight: PromethDesign.windowMinHeight
        )
        .accessibilityIdentifier("prometh.root")
    }
}
