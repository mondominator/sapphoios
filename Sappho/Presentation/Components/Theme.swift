import SwiftUI

// MARK: - Colors
extension Color {
    // Background colors
    static let sapphoBackground = Color(hex: "0A0E1A")
    static let sapphoSurface = Color(hex: "1a1a1a")
    static let sapphoSurfaceElevated = Color(hex: "252525")

    // Primary colors
    static let sapphoPrimary = Color(hex: "3B82F6")

    // Text colors
    static let sapphoTextHigh = Color(hex: "E0E7F1")
    static let sapphoTextMedium = Color(hex: "B0B8C4")
    static let sapphoTextMuted = Color(hex: "9ca3af")

    // Accent colors
    static let sapphoSuccess = Color(hex: "22C55E")
    static let sapphoWarning = Color(hex: "F59E0B")
    static let sapphoError = Color(hex: "EF4444")

    static let sapphoRating = Color(hex: "FBBF26")

    // Primary variants
    static let sapphoPrimaryLight = Color(hex: "60A5FA")
    static let sapphoPrimaryLighter = Color(hex: "87BFF8")
    static let sapphoSecondary = Color(hex: "8B5CF6")
    static let sapphoTeal = Color(hex: "06B6D4")
    static let sapphoPlayingGreen = Color(hex: "34D399")
    static let sapphoSuccessLight = Color(hex: "4CD981")

    // Surface variants
    static let sapphoSurfaceSlate = Color(hex: "1E293B")
    static let sapphoBorder = Color(hex: "374151")
    static let sapphoDisabled = Color(hex: "4B5563")

    // Library category gradients
    static let sapphoCategoryBlueStart = Color(hex: "3B82F6")
    static let sapphoCategoryBlueEnd = Color(hex: "2563EB")
    static let sapphoCategoryTealStart = Color(hex: "26A69A")
    static let sapphoCategoryTealEnd = Color(hex: "00897B")
    static let sapphoCategoryGrayStart = Color(hex: "374151")
    static let sapphoCategoryGrayEnd = Color(hex: "1F2937")

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
    // Display fonts - large prominent text
    static let sapphoDisplayMedium = Font.system(size: 40, weight: .bold, design: .rounded)

    // Title fonts
    static let sapphoTitle = Font.system(size: 28, weight: .bold)
    static let sapphoTitleMedium = Font.system(size: 24, weight: .bold)
    static let sapphoTitleSmall = Font.system(size: 22, weight: .bold)

    // Headline fonts
    static let sapphoHeadline = Font.system(size: 20, weight: .semibold)
    static let sapphoHeadlineMedium = Font.system(size: 18, weight: .semibold)

    // Subheadline fonts
    static let sapphoSubheadline = Font.system(size: 16, weight: .medium)
    static let sapphoSubheadlineRounded = Font.system(size: 16, weight: .bold, design: .rounded)

    // Body fonts
    static let sapphoBody = Font.system(size: 15, weight: .regular)
    static let sapphoBodyMedium = Font.system(size: 15, weight: .medium)
    static let sapphoBodySemibold = Font.system(size: 15, weight: .semibold)

    // Detail fonts
    static let sapphoDetail = Font.system(size: 14, weight: .regular)
    static let sapphoDetailMedium = Font.system(size: 14, weight: .medium)
    static let sapphoDetailSemibold = Font.system(size: 14, weight: .semibold)

    // Caption fonts
    static let sapphoCaption = Font.system(size: 13, weight: .regular)
    static let sapphoCaptionSemibold = Font.system(size: 13, weight: .semibold)

    // Small fonts
    static let sapphoSmall = Font.system(size: 11, weight: .regular)
    static let sapphoSmallMedium = Font.system(size: 11, weight: .medium)

    // Tiny fonts - badges, labels
    static let sapphoTiny = Font.system(size: 10, weight: .regular)
    static let sapphoTinyBold = Font.system(size: 10, weight: .bold)
    static let sapphoTinySemibold = Font.system(size: 10, weight: .semibold)
    static let sapphoMicro = Font.system(size: 8, weight: .regular)
    static let sapphoTinyDetail = Font.system(size: 12, weight: .regular)

    // Icon fonts - for SF Symbol sizing
    static let sapphoIconXXLarge = Font.system(size: 48)
    static let sapphoIconXLarge = Font.system(size: 40)
    static let sapphoIconHuge = Font.system(size: 36)
    static let sapphoIconLarge = Font.system(size: 32)
    static let sapphoIconMedium = Font.system(size: 22)
    static let sapphoIconSmall = Font.system(size: 20)
    static let sapphoIconTiny = Font.system(size: 18)
    static let sapphoIconMini = Font.system(size: 12)

    // Player-specific fonts
    static let sapphoPlayerSpeed = Font.system(size: 48, weight: .bold, design: .rounded)
    static let sapphoPlayerTimerDisplay = Font.system(size: 40, weight: .bold, design: .rounded)
    static let sapphoPlayerTimerLabel = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let sapphoPlayerPlayButton = Font.system(size: 28)
}

// MARK: - View Modifiers
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
                .font(.sapphoIconXXLarge)
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
                .font(.sapphoIconXXLarge)
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
