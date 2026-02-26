import SwiftUI

struct WorldView: View {
    @ObservedObject var appState: AppState
    var body: some View {
        VStack {
            Text("World")
                .font(AppTheme.title)
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
