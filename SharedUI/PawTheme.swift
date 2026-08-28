import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PawTheme {
    static let adventureBlue = Color(hex: 0x3568E8)
    static let energyYellow = Color(hex: 0xFFD65A)
    static let grassGreen = Color(hex: 0x68C95B)
    static let coralOrange = Color(hex: 0xFF795F)
    static let teal = Color(hex: 0x2FB6C4)

    static let background = Color.dynamic(light: 0xFFF9E9, dark: 0x0E1424)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x18213A)
    static let surfaceRaised = Color.dynamic(light: 0xF3F6FF, dark: 0x202B49)
    static let ink = Color.dynamic(light: 0x17213B, dark: 0xF3F7FF)
    static let inkSecondary = Color.dynamic(light: 0x66708A, dark: 0xAAB5D2)
    static let line = Color.dynamic(light: 0xE4E9F5, dark: 0x303B5B)

    static let habitatGradient = LinearGradient(
        colors: [Color.dynamic(light: 0xC9EEFF, dark: 0x203B56), Color.dynamic(light: 0xE8E1FF, dark: 0x302A54)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
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
            .shadow(color: PawTheme.ink.opacity(0.08), radius: 14, x: 0, y: 7)
    }
}

struct SectionKicker: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.3)
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
