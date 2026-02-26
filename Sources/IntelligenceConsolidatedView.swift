import SwiftUI

struct IntelligenceConsolidatedView: View {
    @ObservedObject var appState: AppState
    var body: some View {
        VStack {
            Text("Intelligence")
                .font(AppTheme.title)
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
