import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PawTheme {
    static let adventureBlue = Color.dynamic(light: 0x376957, dark: 0x9BCBB0)
    static let energyYellow = Color(hex: 0xD5AD63)
    static let grassGreen = Color.dynamic(light: 0x64856A, dark: 0xA1C29A)
    static let coralOrange = Color.dynamic(light: 0xBC745B, dark: 0xD8A08A)
    static let teal = Color.dynamic(light: 0x5A8A8D, dark: 0x9BC5C7)

    static let background = Color.dynamic(light: 0xF7F7F2, dark: 0x151917)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x202722)
    static let surfaceRaised = Color.dynamic(light: 0xECEFE8, dark: 0x2B342D)
    static let ink = Color.dynamic(light: 0x23382B, dark: 0xF0F3ED)
    static let inkSecondary = Color.dynamic(light: 0x737B70, dark: 0xADB8AA)
    static let line = Color.dynamic(light: 0xE0E5DC, dark: 0x384239)
    static let buttonForeground = Color.dynamic(light: 0xFFFFFF, dark: 0x193323)

    static let habitatGradient = LinearGradient(
        colors: [Color.dynamic(light: 0xEFF7F2, dark: 0x2B3D36), Color.dynamic(light: 0xFAF3E8, dark: 0x30352E)],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension PawPaceHeartRateZone {
    var tint: Color {
        switch self {
        case .recovery: PawTheme.teal
        case .endurance: PawTheme.grassGreen
        case .tempo: PawTheme.energyYellow
        case .threshold: PawTheme.coralOrange
        case .peak: .pink
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    static func dynamic(light: UInt, dark: UInt) -> Color {
#if os(watchOS)
        Color(hex: dark)
#else
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1
            )
        })
#endif
    }
}

extension View {
    func pawCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PawTheme.line.opacity(0.6), lineWidth: 0.5)
            }
    }
}

struct SectionKicker: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PawTheme.inkSecondary)
            }
        }
        .foregroundStyle(PawTheme.ink)
    }
}

struct MetricPill: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = PawTheme.adventureBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(value)
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }
            .foregroundStyle(tint)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(PawTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
