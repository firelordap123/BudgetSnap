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
                        Text("Screenshot-based budgeting with review-first AI imports.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.top, 34)

                    VStack(spacing: 12) {
                        SetupStep(icon: "camera.viewfinder", title: "Import screenshots", detail: "Select banking, credit card, receipt, or statement screenshots.")
                        SetupStep(icon: "sparkles", title: "Review AI results", detail: "Parsed charges stay pending until you accept them.")
                        SetupStep(icon: "brain.head.profile", title: "Remember corrections", detail: "Merchant rules learn your preferred categories over time.")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Monthly budget", systemImage: "wallet.pass.fill")
                            .font(.headline)
                        TextField("Monthly budget", text: $totalBudget)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                            .padding(14)
                            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
