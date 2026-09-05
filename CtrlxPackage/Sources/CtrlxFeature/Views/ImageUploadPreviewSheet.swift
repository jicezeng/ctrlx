#if os(iOS)
    import CtrlxCommon
    import SwiftUI
    import UIKit

    struct ImageUploadPreviewSheet: View {
        @Binding var images: [ImageUploadDraftItem]
        let isUploading: Bool
        let isConnected: Bool
        @Binding var uploadErrorMessage: String?
        let onCancel: () -> Void
        let onSend: () -> Void

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        ForEach(images) { item in
                            imageRow(item)
                        }
                    } footer: {
                        Text("\(images.count) image(s), \(formattedTotalSize) after compression")
                    }
                }
                .navigationTitle("Send Images")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                            .disabled(isUploading)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send", action: onSend)
                            .disabled(images.isEmpty || isUploading || !isConnected)
                    }
                }
                .overlay {
                    if isUploading {
                        ProgressView("Sending…")
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }
                .alert("Image Upload Failed", isPresented: .init(
                    get: { uploadErrorMessage != nil },
                    set: { if !$0 { uploadErrorMessage = nil } }
                )) {
                    Button("OK") { uploadErrorMessage = nil }
                } message: {
                    if let uploadErrorMessage {
                        Text(uploadErrorMessage)
                    }
                }
            }
        }

        private var formattedTotalSize: String {
            let bytes = images.reduce(0) { $0 + $1.image.data.count }
            return ByteCountFormatter.string(
                fromByteCount: Int64(bytes),
                countStyle: .file
            )
        }

        private func imageRow(_ item: ImageUploadDraftItem) -> some View {
            HStack(spacing: 12) {
                if let image = UIImage(data: item.image.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .lineLimit(2)
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(item.image.data.count),
                        countStyle: .file
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    images.removeAll { $0.id == item.id }
                } label: {
                    Label("Remove \(item.displayName)", symbol: .xmarkCircleFill)
                        .labelStyle(.iconOnly)
                }
                .disabled(isUploading)
            }
            .padding(.vertical, 4)
        }
    }
#endif
