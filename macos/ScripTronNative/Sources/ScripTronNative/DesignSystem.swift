import SwiftUI

extension Color {
    static let appBackground = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let sidebarBackground = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let surfaceSoft = Color(red: 0.93, green: 0.96, blue: 0.97)
    static let primaryGreen = Color(red: 0.0, green: 0.47, blue: 0.40)
    static let projectRail = Color(red: 0.91, green: 0.94, blue: 0.96)
    static let projectPanel = Color(red: 0.94, green: 0.965, blue: 0.975)
    static let editorBackground = Color(red: 0.975, green: 0.982, blue: 0.988)
    static let hairline = Color(red: 0.82, green: 0.85, blue: 0.88)
}

extension View {
    func acrylicPanel(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 14)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 14 : 15, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 18 : 20)
            .frame(height: compact ? 38 : 48)
            .background(Color.primaryGreen.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: compact ? 12 : 16))
    }
}

struct SheetActionButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(primary ? .white : Color.primary)
            .frame(width: 92, height: 38)
            .background(
                primary
                    ? Color.primaryGreen.opacity(configuration.isPressed ? 0.82 : 1)
                    : Color.surfaceSoft.opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

struct SidebarButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(active ? Color.primaryGreen : .secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
                .background(active ? Color.primaryGreen.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
