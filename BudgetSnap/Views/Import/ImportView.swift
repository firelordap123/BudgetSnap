import PhotosUI
import SwiftUI
import UIKit

struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []
    @State private var showReview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    importActions

                    if !selectedImageData.isEmpty {
                        selectedImagesPreview
                        processButton
                    }

                    if let error = store.importErrorMessage {
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
            .onChange(of: selectedItems) { _, newItems in
                Task { await loadSelectedImages(from: newItems) }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: "camera.viewfinder")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.accent)
            Text("Turn screenshots into transactions.")
                .font(.title2.weight(.bold))
            Text("Select screenshots from your photo library to extract transactions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .premiumCard(padding: 20)
    }

    private var importActions: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 8, matching: .images) {
                Label("Photo Library", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                selectedImageData.removeAll()
                selectedItems.removeAll()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(selectedImageData.isEmpty)
        }
    }

    private var processButton: some View {
        Button {
            Task {
                await store.importScreenshots(selectedImageData)
                selectedImageData.removeAll()
                selectedItems.removeAll()
                showReview = true
            }
        } label: {
            HStack {
                if store.isImporting { ProgressView().tint(.white) }
                Text(store.isImporting ? "Processing..." : "Process \(selectedImageData.count) Screenshot\(selectedImageData.count == 1 ? "" : "s")")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isImporting)
    }

    private var selectedImagesPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Screenshots")
                .font(.headline)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(selectedImageData.enumerated()), id: \.offset) { index, data in
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 116, height: 158)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        selectedImageData.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.56))
                                    }
                                    .padding(7)
                                }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .premiumCard()
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var dataList: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                dataList.append(data)
            }
        }
        selectedImageData = dataList
    }
}
