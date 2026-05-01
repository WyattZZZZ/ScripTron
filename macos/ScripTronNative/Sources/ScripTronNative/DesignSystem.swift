import SwiftUI

extension Color {
    static let appBackground = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let sidebarBackground = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let surfaceSoft = Color(red: 0.93, green: 0.96, blue: 0.97)
    static let primaryGreen = Color(red: 0.0, green: 0.47, blue: 0.40)
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
