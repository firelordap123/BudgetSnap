import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var totalBudget = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("BudgetSnap")
                            .font(.system(size: 44, weight: .bold, design: .serif))
                            .foregroundStyle(AppTheme.ink)
                        Text("Simple budgeting, one screenshot at a time.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.top, 34)

                    VStack(spacing: 12) {
                        SetupStep(icon: "camera.viewfinder", title: "Import screenshots", detail: "Select banking, credit card, or statement screenshots.")
                        SetupStep(icon: "checkmark.circle", title: "Review imports", detail: "Imported transactions stay pending until you accept them.")
                        SetupStep(icon: "bookmark.fill", title: "Remember corrections", detail: "Your category choices are saved for future imports.")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Monthly budget", systemImage: "wallet.pass.fill")
                            .font(.headline)
                        TextField("Monthly budget", text: $totalBudget)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                            .padding(14)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .premiumCard()

                    Button {
                        let value = Decimal(string: totalBudget) ?? 0
                        store.updateTotalBudget(value)
                        store.didCompleteSetup = true
                    } label: {
                        Label("Start Budgeting", systemImage: "arrow.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(22)
            }
            .background(AppTheme.background.ignoresSafeArea())
        }
    }
}

private struct SetupStep: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .premiumCard(padding: 14)
    }
}
