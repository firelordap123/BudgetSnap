import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Categories") {
                    HStack {
                        TextField("New category", text: $newCategoryName)
                        Button("Add") {
                            store.addCategory(name: newCategoryName)
                            newCategoryName = ""
                        }
                    }

                    ForEach(store.allCategories) { category in
                        CategorySettingsRow(category: category)
                    }
                }

                Section("Saved Rules") {
                    if store.rules.isEmpty {
                        Text("No saved rules yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.rules) { rule in
                            RuleRow(rule: rule)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
        }
    }
}

private struct CategorySettingsRow: View {
    @EnvironmentObject private var store: AppStore
    @State var category: SpendingCategory

    var body: some View {
        HStack {
            Label(category.name, systemImage: category.systemImage)
                .foregroundStyle(category.color)
            Spacer()
            Toggle("Active", isOn: Binding(
                get: { category.isActive },
                set: {
                    category.isActive = $0
                    store.updateCategory(category)
                }
            ))
            .labelsHidden()
        }
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var store: AppStore
    @State var rule: CategorizationRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.normalizedMerchantName)
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.category(for: rule.categoryID)?.name ?? "Category")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                Spacer()
            }

            Picker("Category", selection: Binding(
                get: { rule.categoryID },
                set: {
                    rule.categoryID = $0
                    store.updateRule(rule)
                }
            )) {
                ForEach(store.categories) { category in
                    Text(category.name).tag(category.id)
                }
            }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    store.deleteRule(rule)
                } label: {
                    Image(systemName: "trash")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
