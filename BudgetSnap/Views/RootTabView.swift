import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.didCompleteSetup {
                mainTabs
            } else {
                SetupView()
            }
        }
        .tint(AppTheme.accent)
    }

    private var mainTabs: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            ImportView()
                .tabItem { Label("Import", systemImage: "building.columns") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle.fill") }

            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "slider.horizontal.3") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
