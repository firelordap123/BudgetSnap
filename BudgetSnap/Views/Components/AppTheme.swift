import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.965, green: 0.955, blue: 0.935)
    static let surface = Color(red: 0.995, green: 0.99, blue: 0.975)
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.14)
    static let muted = Color(red: 0.47, green: 0.48, blue: 0.48)
    static let accent = Color(red: 0.05, green: 0.38, blue: 0.36)
    static let warning = Color(red: 0.79, green: 0.48, blue: 0.16)
    static let danger = Color(red: 0.68, green: 0.18, blue: 0.16)
}

struct PremiumCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.black.opacity(0.045), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.055), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func premiumCard(padding: CGFloat = 16) -> some View {
        modifier(PremiumCardModifier(padding: padding))
    }
}
