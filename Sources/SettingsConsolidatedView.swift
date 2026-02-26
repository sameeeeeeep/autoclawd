import SwiftUI

struct SettingsConsolidatedView: View {
    @ObservedObject var appState: AppState
    var body: some View {
        VStack {
            Text("Settings")
                .font(AppTheme.title)
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
