import SwiftUI

struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showReview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 13) {
                        Image(systemName: "building.columns")
                            .font(.largeTitle)
                            .foregroundStyle(AppTheme.accent)
                        Text("Connect your bank.")
                            .font(.title2.weight(.bold))
                        Text("Link your accounts to automatically import transactions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .premiumCard(padding: 20)

                    if let error = store.syncErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.danger)
                            .premiumCard()
                    }
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Import")
            .navigationDestination(isPresented: $showReview) {
                ReviewImportView()
            }
        }
    }
}
