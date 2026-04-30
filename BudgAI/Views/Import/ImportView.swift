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

                    pipelineCard

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
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.accent)
            Text("Turn screenshots into budget-ready transactions.")
                .font(.title2.weight(.bold))
            Text("Images go to your backend import API. Parsed charges return here as pending review cards.")
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
        }
        .premiumCard()
    }

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Backend handoff", systemImage: "server.rack")
                .font(.headline)
            PipelineRow(number: "1", title: "Upload images", detail: "POST multipart screenshots to your API.")
            PipelineRow(number: "2", title: "OCR + LLM parse", detail: "Return strict transaction JSON with confidence and raw text.")
            PipelineRow(number: "3", title: "Review state", detail: "Nothing posts until the user accepts parsed charges.")
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

private struct PipelineRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
