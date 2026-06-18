import AVFoundation
import SwiftUI

struct PairingView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showingScanner = false
    @State private var pastedPayload = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("Pair with Volio Desktop")
                        .font(.title2.bold())
                    Text("Open Volio Desktop on your Mac, choose Connect iPhone, then scan the QR code.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showingScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste pairing payload")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $pastedPayload)
                        .frame(height: 96)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    Button("Pair from Pasted Text") {
                        pair(from: pastedPayload)
                    }
                    .disabled(pastedPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Volio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView(
                    onCancel: { showingScanner = false },
                    onCode: { value in
                    showingScanner = false
                    pair(from: value)
                    }
                )
            }
        }
    }

    private func pair(from rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if pairFromURL(trimmed) {
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            errorMessage = "That pairing code could not be read."
            return
        }
        do {
            let payload = try JSONDecoder.volio.decode(PairingPayload.self, from: data)
            guard payload.type == "volio-ios-pairing", !payload.baseURL.isEmpty, !payload.token.isEmpty else {
                errorMessage = "That QR code is not a Volio pairing code."
                return
            }
            session.pair(with: payload)
            dismiss()
        } catch {
            errorMessage = "That pairing code could not be read."
        }
    }

    private func pairFromURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "volio", url.host == "pair" else {
            return false
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String {
            items.first(where: { $0.name == name })?.value ?? ""
        }
        let payload = PairingPayload(
            type: "volio-ios-pairing",
            version: 1,
            baseURL: query("base_url"),
            token: query("token"),
            hostName: query("host_name").isEmpty ? nil : query("host_name")
        )
        guard !payload.baseURL.isEmpty, !payload.token.isEmpty else {
            errorMessage = "That QR code is not a Volio pairing code."
            return true
        }
        session.pair(with: payload)
        dismiss()
        return true
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCancel: () -> Void
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCancel = onCancel
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCancel: (() -> Void)?
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        let closeButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Close"
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        closeButton.configuration = config
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        ])
        Task.detached { [session] in session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        session.stopRunning()
        onCode?(value)
    }

    @objc private func closeTapped() {
        session.stopRunning()
        onCancel?()
    }
}
