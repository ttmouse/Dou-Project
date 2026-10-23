import SwiftUI

/// Shared input treatment for app-owned dialog forms.
struct AppDialogTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .foregroundColor(AppTheme.text)
    }
}
