#if os(iOS)
    import SwiftUI
    import UIKit

    /// Minimal UIKit bridge for taking one photo. The system owns permission
    /// presentation and capture UI; CtrlX only receives the confirmed image.
    struct CameraImagePicker: UIViewControllerRepresentable {
        let onCapture: (Data) -> Void
        let onCancel: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onCapture: onCapture, onCancel: onCancel)
        }

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: UIImagePickerController, context _: Context) {}

        final class Coordinator: NSObject, UIImagePickerControllerDelegate,
            UINavigationControllerDelegate
        {
            private let onCapture: (Data) -> Void
            private let onCancel: () -> Void

            init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
                self.onCapture = onCapture
                self.onCancel = onCancel
            }

            func imagePickerController(
                _: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                guard
                    let image = info[.originalImage] as? UIImage,
                    let data = image.jpegData(compressionQuality: 0.95)
                else {
                    onCancel()
                    return
                }
                onCapture(data)
            }

            func imagePickerControllerDidCancel(_: UIImagePickerController) {
                onCancel()
            }
        }
    }
#endif
