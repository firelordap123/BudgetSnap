import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if store.dashboardSummary.pendingReviewCount > 0 {
                            NavigationLink {
                                ReviewImportView()
                            } label: {
                                ReviewQueueBanner(count: store.dashboardSummary.pendingReviewCount)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Category Spending")
                            .font(.title3.weight(.bold))
                            .padding(.top, 4)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(store.dashboardSummary.categorySummaries.prefix(8)) { summary in
                                CategorySpendTile(summary: summary)
                            }
                        }

                        Text("Recent Transactions")
                            .font(.title3.weight(.bold))
                            .padding(.top, 8)

                        if store.dashboardSummary.recentTransactions.isEmpty {
                            ContentUnavailableView("No spending yet", systemImage: "tray", description: Text("Accepted transactions will appear here."))
                                .premiumCard()
                        } else {
                            ForEach(store.dashboardSummary.recentTransactions) { transaction in
                                TransactionCard(transaction: transaction)
                            }
                        }
                    } header: {
                        summaryCard
                            .padding(.bottom, 4)
                            .background(AppTheme.background)
                    }
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
        }
    }

    private var summaryCard: some View {
        let summary = store.dashboardSummary
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Formatters.monthTitle.string(from: summary.month))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    Text("Monthly Budget")
                        .font(.title2.weight(.bold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(summary.percentUsed * 100))%")
                        .font(.title2.weight(.bold))
                    Text("used")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            Text(Formatters.currencyString(summary.totalSpent))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.75)

            ProgressView(value: min(summary.percentUsed, 1))
                .tint(summary.percentUsed > 1 ? AppTheme.danger : AppTheme.accent)
                .scaleEffect(x: 1, y: 1.8, anchor: .center)
                .padding(.vertical, 4)

            HStack {
                MetricPill(title: "Budget", value: Formatters.currencyString(summary.totalBudget), icon: "target")
                MetricPill(title: "Remaining", value: Formatters.currencyString(summary.remaining), icon: "wallet.pass")
            }
        }
        .premiumCard(padding: 20)
    }
}

private struct ReviewQueueBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(AppTheme.warning.opacity(0.16), in: Circle())
                .foregroundStyle(AppTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) transactions need review")
                    .font(.headline)
                Text("Approve before they affect your budget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .premiumCard()
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CategorySpendTile: View {
    let summary: CategorySpendSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: summary.category.systemImage)
                    .foregroundStyle(summary.category.color)
                    .frame(width: 30, height: 30)
                    .background(summary.category.color.opacity(0.13), in: Circle())
                Spacer()
                Text("\(Int(summary.percentUsed * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(summary.percentUsed > 1 ? AppTheme.danger : .secondary)
            }

            Text(summary.category.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("\(Formatters.currencyString(summary.spent)) of \(Formatters.currencyString(summary.budget))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ProgressView(value: min(summary.percentUsed, 1))
                .tint(summary.percentUsed > 1 ? AppTheme.danger : summary.category.color)
        }
        .frame(minHeight: 132)
        .premiumCard(padding: 14)
    }
}
