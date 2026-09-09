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
                .navigationDestination(for: ImageUploadReviewRoute.self) { route in
                    if let item = images.first(where: { $0.id == route.imageID }) {
                        ImageUploadReviewView(item: item)
                    } else {
                        ContentUnavailableView(
                            "Image Unavailable",
                            systemImage: "photo",
                            description: Text("Return to the image list and choose another image.")
                        )
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
                NavigationLink(value: ImageUploadReviewRoute(imageID: item.id)) {
                    ImageUploadPreviewRow(item: item)
                }
                .accessibilityLabel("Preview \(item.displayName)")
                .accessibilityHint("Shows the compressed image that will be sent")
                .disabled(isUploading)

                Button(role: .destructive) {
                    images.removeAll { $0.id == item.id }
                } label: {
                    Label("Remove \(item.displayName)", symbol: .xmarkCircleFill)
                        .labelStyle(.iconOnly)
                }
                .disabled(isUploading)
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
    }

    private struct ImageUploadReviewRoute: Hashable {
        let imageID: UUID
    }

    private struct ImageUploadPreviewRow: View {
        let item: ImageUploadDraftItem

        var body: some View {
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
                    Text(Self.formattedSize(of: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(.rect)
        }

        private static func formattedSize(of item: ImageUploadDraftItem) -> String {
            ByteCountFormatter.string(
                fromByteCount: Int64(item.image.data.count),
                countStyle: .file
            )
        }
    }

    private struct ImageUploadReviewView: View {
        let item: ImageUploadDraftItem

        var body: some View {
            Group {
                if let image = UIImage(data: item.image.data) {
                    ZoomableImageView(
                        image: image,
                        imageID: item.id,
                        accessibilityLabel: item.displayName
                    )
                } else {
                    ContentUnavailableView(
                        "Image Unavailable",
                        systemImage: "photo",
                        description: Text("This image could not be decoded.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(.black)
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Text("Compressed preview · \(formattedSize) · Pinch or double-tap to zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }

        private var formattedSize: String {
            ByteCountFormatter.string(
                fromByteCount: Int64(item.image.data.count),
                countStyle: .file
            )
        }
    }

    private struct ZoomableImageView: UIViewRepresentable {
        let image: UIImage
        let imageID: UUID
        let accessibilityLabel: String

        func makeCoordinator() -> Coordinator {
            Coordinator(imageID: imageID)
        }

        func makeUIView(context: Context) -> UIScrollView {
            let scrollView = UIScrollView()
            scrollView.delegate = context.coordinator
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 6
            scrollView.bouncesZoom = true
            scrollView.decelerationRate = .fast
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.backgroundColor = .black

            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = accessibilityLabel
            scrollView.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ])

            let doubleTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleDoubleTap(_:))
            )
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            context.coordinator.imageView = imageView
            return scrollView
        }

        func updateUIView(_ scrollView: UIScrollView, context: Context) {
            context.coordinator.imageView?.accessibilityLabel = accessibilityLabel

            guard context.coordinator.imageID != imageID else { return }
            context.coordinator.imageID = imageID
            context.coordinator.imageView?.image = image
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        }

        final class Coordinator: NSObject, UIScrollViewDelegate {
            var imageID: UUID
            weak var imageView: UIImageView?

            init(imageID: UUID) {
                self.imageID = imageID
            }

            func viewForZooming(in _: UIScrollView) -> UIView? {
                imageView
            }

            @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
                guard
                    let scrollView = recognizer.view as? UIScrollView,
                    let imageView
                else { return }

                if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                    scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                    return
                }

                let targetScale = min(3, scrollView.maximumZoomScale)
                let location = recognizer.location(in: imageView)
                let zoomSize = CGSize(
                    width: scrollView.bounds.width / targetScale,
                    height: scrollView.bounds.height / targetScale
                )
                let zoomRect = CGRect(
                    x: location.x - zoomSize.width / 2,
                    y: location.y - zoomSize.height / 2,
                    width: zoomSize.width,
                    height: zoomSize.height
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
#endif
