import SwiftUI
import Vision
import VisionKit

struct InviteQRCodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    InviteQRCodeScannerRepresentable { code in
                        onScan(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    unsupportedView
                }
            }
            .navigationTitle("invite.join.scan.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.primaryText)
                }
            }
        }
    }

    private var unsupportedView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.discoverViolet)

            Text("invite.join.scan.unsupported")
                .font(Font.App.subheadline())
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InviteQRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> InviteQRScannerViewController {
        let controller = InviteQRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: InviteQRScannerViewController, context: Context) {}

    final class Coordinator: NSObject, InviteQRScannerDelegate {
        private let onScan: (String) -> Void
        private var didHandleScan = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func inviteQRScanner(_ scanner: InviteQRScannerViewController, didScan payload: String) {
            guard !didHandleScan else { return }
            didHandleScan = true
            onScan(payload)
        }
    }
}

private protocol InviteQRScannerDelegate: AnyObject {
    func inviteQRScanner(_ scanner: InviteQRScannerViewController, didScan payload: String)
}

private final class InviteQRScannerViewController: UIViewController {
    weak var delegate: InviteQRScannerDelegate?

    private var scanner: DataScannerViewController?
    private var didHandleScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        scanner.delegate = self
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanner.didMove(toParent: self)
        self.scanner = scanner
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        try? scanner?.startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner?.stopScanning()
    }

    func handleRecognizedItem(_ item: RecognizedItem) {
        guard !didHandleScan else { return }
        guard case .barcode(let barcode) = item,
              let payload = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !payload.isEmpty
        else { return }

        didHandleScan = true
        scanner?.stopScanning()
        delegate?.inviteQRScanner(self, didScan: payload)
    }
}

extension InviteQRScannerViewController: DataScannerViewControllerDelegate {
    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didTapOn item: RecognizedItem
    ) {
        handleRecognizedItem(item)
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        guard let item = addedItems.first else { return }
        handleRecognizedItem(item)
    }
}
