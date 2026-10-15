import SwiftUI

/// File overview:
/// The small Lingrove affordance shown just outside a supported text field. It renders the whale
/// tail mark on a dark rounded chip while leaving field-edge placement to its controller.
struct FieldEdgeIconIndicatorView: View {
    // Keep the field-edge indicator at its existing compact 14-point footprint.
    private let side: CGFloat = 14
    // The source artwork's 82/395 corner radius scales to about 2.9 points at this size.
    private let cornerRadius: CGFloat = 3

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.18, green: 0.19, blue: 0.21))
            Image("ActivationIndicatorWhaleTail")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .foregroundStyle(.white)
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .fixedSize()
    }
}
