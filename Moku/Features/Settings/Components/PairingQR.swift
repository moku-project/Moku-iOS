import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// A sharp QR code for a pairing link.
struct PairingQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 200)
                .accessibilityLabel("Pairing QR code")
        }
    }

    private static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
            let image = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Camera view that reports the first QR code it reads.
struct PairingScanner: View {
    let found: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerView { text in
                        found(text)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    EmptyState(
                        systemImage: "camera",
                        message:
                            "Allow camera access in Settings, or type the address and code instead")
                }
            }
            .navigationTitle("Scan Pairing Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct ScannerView: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(
            _ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for case .barcode(let code) in items {
                guard !done, let text = code.payloadStringValue else { continue }
                done = true
                scanner.stopScanning()
                found(text)
            }
        }
    }
}
