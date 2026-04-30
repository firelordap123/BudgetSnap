import SwiftUI

struct CategoryChip: View {
    let category: SpendingCategory?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category?.systemImage ?? "questionmark.circle")
            Text(category?.name ?? "Uncategorized")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((category?.color ?? .secondary).opacity(0.14), in: Capsule())
        .foregroundStyle(category?.color ?? .secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}
