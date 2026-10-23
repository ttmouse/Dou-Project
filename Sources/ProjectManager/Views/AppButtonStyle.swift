import SwiftUI

struct ToolbarIcon: View {
    let systemName: String
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct AppButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isPrimary ? Color.clear : AppTheme.border, lineWidth: 1)
            }
            .foregroundColor(isPrimary ? .white : AppTheme.text)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPrimary {
            return isPressed ? AppTheme.accent.opacity(0.82) : AppTheme.accent
        }
        return isPressed ? AppTheme.buttonHover : AppTheme.buttonBackground
    }
}

struct IconButtonStyle: ButtonStyle {
    var isSelected = false
    var iconSize: CGFloat = 18
    var buttonSize: CGFloat = 30
    var buttonWidth: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        IconButtonStyleBody(
            configuration: configuration,
            isSelected: isSelected,
            iconSize: iconSize,
            buttonSize: buttonSize,
            buttonWidth: buttonWidth
        )
    }
}

struct HoverBackgroundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBackgroundButtonBody(configuration: configuration)
    }
}

private struct HoverBackgroundButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered || configuration.isPressed ? AppTheme.buttonHover : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
    }
}

private struct IconButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let buttonWidth: CGFloat?

    var body: some View {
        IconButtonSurface(
            isSelected: isSelected,
            isPressed: configuration.isPressed,
            iconSize: iconSize,
            buttonSize: buttonSize,
            buttonWidth: buttonWidth
        ) {
            configuration.label
        }
    }
}

struct IconButtonSurface<Label: View>: View {
    let isSelected: Bool
    let isPressed: Bool
    let iconSize: CGFloat
    let buttonSize: CGFloat?
    let buttonWidth: CGFloat?
    let label: Label
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    init(
        isSelected: Bool,
        isPressed: Bool,
        iconSize: CGFloat,
        buttonSize: CGFloat?,
        buttonWidth: CGFloat? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.isSelected = isSelected
        self.isPressed = isPressed
        self.iconSize = iconSize
        self.buttonSize = buttonSize
        self.buttonWidth = buttonWidth
        self.label = label()
    }

    var body: some View {
        label
            .font(.system(size: iconSize, weight: .regular))
            .foregroundColor(isEnabled && isSelected ? AppTheme.icon : AppTheme.secondaryIcon.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, buttonSize == nil ? 8 : 0)
            .frame(width: buttonWidth ?? buttonSize, height: buttonSize ?? 30)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(backgroundColor)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .clear }
        if isPressed { return AppTheme.buttonHover }
        if isHovered { return AppTheme.buttonHover }
        if isSelected { return AppTheme.accent.opacity(0.18) }
        return .clear
    }
}
