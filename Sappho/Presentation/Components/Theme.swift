import SwiftUI

// MARK: - Colors
extension Color {
    // Background colors
    static let sapphoBackground = Color(hex: "0A0E1A")
    static let sapphoBackgroundDeep = Color(hex: "050810")
    static let sapphoSurface = Color(hex: "1a1a1a")
    static let sapphoSurfaceElevated = Color(hex: "252525")
    static let sapphoSurfaceDialog = Color(hex: "2a2a2a")

    // Primary colors
    static let sapphoPrimary = Color(hex: "3B82F6")
    static let sapphoPrimaryDark = Color(hex: "2563EB")
    static let sapphoSecondary = Color(hex: "8B5CF6")

    // Text colors
    static let sapphoTextHigh = Color(hex: "E0E7F1")
    static let sapphoTextMedium = Color(hex: "B0B8C4")
    static let sapphoTextMuted = Color(hex: "9ca3af")
    static let sapphoTextDisabled = Color(hex: "6b7280")

    // Accent colors
    static let sapphoSuccess = Color(hex: "22C55E")
    static let sapphoWarning = Color(hex: "F59E0B")
    static let sapphoError = Color(hex: "EF4444")

    // Utility
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
extension Font {
    static let sapphoTitle = Font.system(size: 28, weight: .bold)
    static let sapphoHeadline = Font.system(size: 20, weight: .semibold)
    static let sapphoSubheadline = Font.system(size: 16, weight: .medium)
    static let sapphoBody = Font.system(size: 15, weight: .regular)
    static let sapphoCaption = Font.system(size: 13, weight: .regular)
    static let sapphoSmall = Font.system(size: 11, weight: .regular)
}

// MARK: - View Modifiers
struct SapphoCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.sapphoSurface)
            .cornerRadius(12)
    }
}

struct SapphoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sapphoSubheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.sapphoPrimary)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SapphoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sapphoSubheadline)
            .foregroundColor(.sapphoPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.sapphoSurface)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.sapphoPrimary, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

extension View {
    func sapphoCard() -> some View {
        modifier(SapphoCardStyle())
    }
}

// MARK: - Common Components
struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .sapphoPrimary))
                .scaleEffect(1.2)
            Text(message)
                .font(.sapphoCaption)
                .foregroundColor(.sapphoTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sapphoBackground)
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.sapphoError)

            Text(message)
                .font(.sapphoBody)
                .foregroundColor(.sapphoTextMedium)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let retry = retryAction {
                Button("Retry", action: retry)
                    .buttonStyle(SapphoPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sapphoBackground)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.sapphoTextMuted)

            Text(title)
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoTextHigh)

            Text(message)
                .font(.sapphoBody)
                .foregroundColor(.sapphoTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sapphoBackground)
    }
}
