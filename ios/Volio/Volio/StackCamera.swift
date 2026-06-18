import AVFoundation
import SwiftUI
import UIKit

struct StackCameraView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onImportPhotos: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> StackCameraViewController {
        let controller = StackCameraViewController()
        controller.onCapture = onCapture
        controller.onImportPhotos = onImportPhotos
        controller.onClose = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: StackCameraViewController, context: Context) {}
}

final class StackCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((Data) -> Void)?
    var onImportPhotos: (() -> Void)?
    var onClose: (() -> Void)?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "volio.camera.session")
    private let previewContainer = UIView()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let shutter = UIButton(type: .system)
    private let previewImageView = UIImageView()
    private let previewSlot = UIView()
    private let countBadge = UILabel()
    private var capturedCount = 0
    private var isSessionReady = false
    private var isCapturing = false
    private var pendingCapture = false
    private var flashOn = false
    private var lastCaptureOrientation: AVCaptureVideoOrientation = .portrait

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isOpaque = true
        view.insetsLayoutMarginsFromSafeArea = false
        configureOverlay()
        configureCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        updateVideoOrientation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreviewContainer()
        previewLayer?.frame = previewContainer.bounds
    }

    private func configureCamera() {
        setShutterEnabled(true)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            guard let device = discovery.devices.first ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input),
                  self.captureSession.canAddOutput(self.photoOutput) else {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async { self.showCameraUnavailable() }
                return
            }
            self.captureSession.addInput(input)
            self.captureSession.addOutput(self.photoOutput)
            self.photoOutput.maxPhotoQualityPrioritization = .speed
            self.captureSession.commitConfiguration()

            let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
            preview.videoGravity = .resizeAspectFill
            DispatchQueue.main.async {
                preview.frame = self.previewContainer.bounds
                self.previewContainer.layer.insertSublayer(preview, at: 0)
                self.previewLayer = preview
                self.updateVideoOrientation()
            }

            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionReady = true
                self.setShutterEnabled(true)
                if self.pendingCapture {
                    self.pendingCapture = false
                    self.capture()
                }
            }
        }
    }

    private func configureOverlay() {
        previewContainer.backgroundColor = .black
        previewContainer.clipsToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(previewContainer)

        let doneButton = UIButton(type: .system)
        var doneConfig = UIButton.Configuration.filled()
        doneConfig.title = "Done"
        doneConfig.baseForegroundColor = .white
        doneConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.38)
        doneConfig.cornerStyle = .capsule
        doneConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16)
        doneButton.configuration = doneConfig
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        shutter.backgroundColor = .clear
        shutter.layer.cornerRadius = 36
        shutter.layer.borderColor = UIColor.white.cgColor
        shutter.layer.borderWidth = 4
        shutter.addTarget(self, action: #selector(capture), for: .touchUpInside)
        let shutterCore = UIView()
        shutterCore.translatesAutoresizingMaskIntoConstraints = false
        shutterCore.backgroundColor = .white
        shutterCore.layer.cornerRadius = 27
        shutterCore.isUserInteractionEnabled = false
        shutter.addSubview(shutterCore)

        let flashButton = UIButton(type: .system)
        var flashConfig = UIButton.Configuration.filled()
        flashConfig.image = UIImage(systemName: "bolt")
        flashConfig.baseForegroundColor = .white
        flashConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.38)
        flashConfig.cornerStyle = .capsule
        flashConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        flashButton.configuration = flashConfig
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)

        let importButton = UIButton(type: .system)
        var importConfig = UIButton.Configuration.filled()
        importConfig.title = "Photos"
        importConfig.image = UIImage(systemName: "photo.on.rectangle")
        importConfig.imagePadding = 6
        importConfig.baseForegroundColor = .white
        importConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.38)
        importConfig.cornerStyle = .capsule
        importConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 14)
        importButton.configuration = importConfig
        importButton.addTarget(self, action: #selector(importPhotos), for: .touchUpInside)

        previewSlot.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        previewSlot.layer.cornerRadius = 12
        previewSlot.layer.borderWidth = 1
        previewSlot.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        previewSlot.clipsToBounds = false

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.alpha = 0
        previewImageView.clipsToBounds = true
        previewImageView.layer.cornerRadius = 12

        countBadge.text = "0"
        countBadge.textAlignment = .center
        countBadge.textColor = .black
        countBadge.font = .systemFont(ofSize: 12, weight: .bold)
        countBadge.backgroundColor = .white
        countBadge.layer.cornerRadius = 11
        countBadge.clipsToBounds = true
        countBadge.alpha = 0
        countBadge.translatesAutoresizingMaskIntoConstraints = false

        [doneButton, shutter, flashButton, previewSlot, importButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewSlot.addSubview(previewImageView)
        previewSlot.addSubview(countBadge)

        NSLayoutConstraint.activate([
            doneButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            flashButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            flashButton.widthAnchor.constraint(equalToConstant: 40),
            flashButton.heightAnchor.constraint(equalToConstant: 40),

            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutter.widthAnchor.constraint(equalToConstant: 72),
            shutter.heightAnchor.constraint(equalToConstant: 72),
            shutterCore.centerXAnchor.constraint(equalTo: shutter.centerXAnchor),
            shutterCore.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            shutterCore.widthAnchor.constraint(equalToConstant: 54),
            shutterCore.heightAnchor.constraint(equalToConstant: 54),

            previewSlot.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            previewSlot.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),

            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            importButton.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),

            previewSlot.widthAnchor.constraint(equalToConstant: 52),
            previewSlot.heightAnchor.constraint(equalToConstant: 52),
            previewImageView.leadingAnchor.constraint(equalTo: previewSlot.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewSlot.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewSlot.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewSlot.bottomAnchor),
            countBadge.trailingAnchor.constraint(equalTo: previewSlot.trailingAnchor, constant: 7),
            countBadge.topAnchor.constraint(equalTo: previewSlot.topAnchor, constant: -7),
            countBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            countBadge.heightAnchor.constraint(equalToConstant: 22)
        ])

        view.setNeedsLayout()
    }

    private func showCameraUnavailable() {
        setShutterEnabled(false)
    }

    private func setShutterEnabled(_ enabled: Bool) {
        shutter.isEnabled = enabled
        shutter.alpha = enabled ? 1 : 0.45
    }

    @objc private func capture() {
        guard !isCapturing else { return }
        guard isSessionReady else {
            pendingCapture = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        isCapturing = true
        setShutterEnabled(false)
        UIView.animate(withDuration: 0.08, animations: {
            self.shutter.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }, completion: { _ in
            UIView.animate(withDuration: 0.12) {
                self.shutter.transform = .identity
            }
        })

        lastCaptureOrientation = currentVideoOrientation()
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = flashOn ? .on : .off
        settings.photoQualityPrioritization = .speed
        updateVideoOrientation()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func close() {
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
        onClose?()
    }

    @objc private func toggleFlash() {
        flashOn.toggle()
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = flashOn ? .on : .off
        device.unlockForConfiguration()
    }

    @objc private func importPhotos() {
        onImportPhotos?()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor in
                self.finishCapture()
            }
            return
        }

        let orientation = lastCaptureOrientation
        DispatchQueue.global(qos: .userInitiated).async { [weak self, data, orientation] in
            let prepared = Self.preparePhoto(data, orientation: orientation)
            DispatchQueue.main.async {
                self?.completeCapture(jpeg: prepared.jpeg, preview: prepared.image)
            }
        }
    }

    private static func preparePhoto(_ data: Data, orientation: AVCaptureVideoOrientation) -> (jpeg: Data, image: UIImage?) {
        guard let uiImage = UIImage(data: data) else {
            return (data, nil)
        }
        let normalized = normalize(uiImage)
        let oriented = forceOrientation(normalized, for: orientation)
        return (oriented.jpegData(compressionQuality: 0.92) ?? data, oriented)
    }

    private static func normalize(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func forceOrientation(_ image: UIImage, for orientation: AVCaptureVideoOrientation) -> UIImage {
        switch orientation {
        case .landscapeLeft where image.size.height > image.size.width:
            return rotate(image, radians: -.pi / 2)
        case .landscapeRight where image.size.height > image.size.width:
            return rotate(image, radians: .pi / 2)
        default:
            return image
        }
    }

    private static func rotate(_ image: UIImage, radians: CGFloat) -> UIImage {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cgContext.rotate(by: radians)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    @MainActor
    private func completeCapture(jpeg: Data, preview image: UIImage?) {
        capturedCount += 1
        countBadge.text = "\(capturedCount)"
        countBadge.alpha = 1
        if let image {
            updatePreview(image)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        finishCapture()
        let onCapture = onCapture
        DispatchQueue.main.async {
            onCapture?(jpeg)
        }
    }

    @MainActor
    private func finishCapture() {
        isCapturing = false
        setShutterEnabled(isSessionReady)
    }

    private func updatePreview(_ image: UIImage) {
        previewImageView.image = image
        previewImageView.transform = CGAffineTransform(translationX: -22, y: 0).scaledBy(x: 0.88, y: 0.88)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.previewImageView.alpha = 1
            self.previewImageView.transform = .identity
        }
    }

    @objc private func deviceOrientationDidChange() {
        layoutPreviewContainer()
        previewLayer?.frame = previewContainer.bounds
        updateVideoOrientation()
    }

    private func updateVideoOrientation() {
        let orientation = currentVideoOrientation()
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            switch view.window?.windowScene?.interfaceOrientation {
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            case .portraitUpsideDown:
                return .portraitUpsideDown
            default:
                return .portrait
            }
        }
    }

    private func layoutPreviewContainer() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        if bounds.width > bounds.height {
            let height = bounds.height
            let width = min(bounds.width, height * 4.0 / 3.0)
            let left = (bounds.width - width) / 2
            previewContainer.frame = CGRect(x: left, y: 0, width: width, height: height)
        } else {
            let width = bounds.width
            let height = width * 4.0 / 3.0
            let top = max(view.safeAreaInsets.top + 64, (bounds.height - height) * 0.42)
            previewContainer.frame = CGRect(x: 0, y: top, width: width, height: height)
        }
    }
}
