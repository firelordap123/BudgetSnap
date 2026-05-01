import SwiftUI

extension Color {
    init(light: Color, dark: Color) {
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

enum AppTheme {
    static let background = Color(
        light: Color(red: 0.965, green: 0.955, blue: 0.935),
        dark:  Color(red: 0.11,  green: 0.11,  blue: 0.12)
    )
    static let surface = Color(
        light: Color(red: 0.995, green: 0.990, blue: 0.975),
        dark:  Color(red: 0.17,  green: 0.17,  blue: 0.18)
    )
    static let ink = Color(
        light: Color(red: 0.12, green: 0.13, blue: 0.14),
        dark:  Color(red: 0.95, green: 0.94, blue: 0.92)
    )
    static let muted = Color(
        light: Color(red: 0.47, green: 0.48, blue: 0.48),
        dark:  Color(red: 0.62, green: 0.63, blue: 0.64)
    )
    static let accent  = Color(red: 0.05, green: 0.38, blue: 0.36)
    static let warning = Color(red: 0.79, green: 0.48, blue: 0.16)
    static let danger  = Color(red: 0.68, green: 0.18, blue: 0.16)
}

struct PremiumCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.055), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func premiumCard(padding: CGFloat = 16) -> some View {
        modifier(PremiumCardModifier(padding: padding))
    }
}
