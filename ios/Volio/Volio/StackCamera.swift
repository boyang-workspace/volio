import AVFoundation
import SwiftUI
import UIKit

struct StackCameraView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> StackCameraViewController {
        let controller = StackCameraViewController()
        controller.onCapture = onCapture
        controller.onClose = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: StackCameraViewController, context: Context) {}
}

final class StackCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((Data) -> Void)?
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

    // Guide frame + focus controls
    private var currentDevice: AVCaptureDevice?
    private let guideView = UIView()
    private var focusIndicator: UIView?
    private var isAEAFLocked = false

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
        layoutPreviewContainer()
        previewLayer?.frame = previewContainer.bounds
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreviewContainer()
        previewLayer?.frame = previewContainer.bounds
        guideView.frame = previewContainer.frame
        setupGuideCorners()
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
            self.currentDevice = device

            let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
            preview.videoGravity = .resizeAspectFill
            DispatchQueue.main.async {
                preview.frame = self.previewContainer.bounds
                self.previewContainer.layer.insertSublayer(preview, at: 0)
                self.previewLayer = preview
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

        // Guide frame
        guideView.isUserInteractionEnabled = false
        guideView.backgroundColor = .clear
        view.addSubview(guideView)

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

        [doneButton, shutter, flashButton, previewSlot].forEach {
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

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePreviewTap(_:)))
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePreviewLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        previewContainer.addGestureRecognizer(tapGesture)
        previewContainer.addGestureRecognizer(longPressGesture)
    }

    private func showCameraUnavailable() {
        setShutterEnabled(false)
    }

    private func setShutterEnabled(_ enabled: Bool) {
        shutter.isEnabled = enabled
        shutter.alpha = enabled ? 1 : 0.45
    }

    // MARK: - Guide frame

    private func setupGuideCorners() {
        guideView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard guideView.bounds.width > 0, guideView.bounds.height > 0 else { return }

        let shapeLayer = CAShapeLayer()
        shapeLayer.strokeColor = UIColor.white.withAlphaComponent(0.65).cgColor
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 2.5
        shapeLayer.lineCap = .round

        let inset: CGFloat = guideView.bounds.width * 0.08
        let cornerLength: CGFloat = 28
        let rect = guideView.bounds.insetBy(dx: inset, dy: inset)

        let path = UIBezierPath()
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))

        shapeLayer.path = path.cgPath
        guideView.layer.addSublayer(shapeLayer)
    }

    // MARK: - Tap to focus / expose

    @objc private func handlePreviewTap(_ gesture: UITapGestureRecognizer) {
        guard !isAEAFLocked else { return }
        let point = gesture.location(in: previewContainer)
        guard let previewLayer, let device = currentDevice else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {}

        showFocusIndicator(at: point, locked: false)
    }

    @objc private func handlePreviewLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: previewContainer)
        guard let previewLayer, let device = currentDevice else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
            if isAEAFLocked {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                isAEAFLocked = false
                removeFocusIndicator()
            } else {
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                }
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                isAEAFLocked = true
                showFocusIndicator(at: point, locked: true)
            }
            device.unlockForConfiguration()
        } catch {}
    }

    private func showFocusIndicator(at point: CGPoint, locked: Bool) {
        removeFocusIndicator()
        let size: CGFloat = 72
        let indicator = UIView(frame: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        indicator.layer.borderColor = UIColor.systemYellow.cgColor
        indicator.layer.borderWidth = 2
        indicator.layer.cornerRadius = 4
        indicator.backgroundColor = .clear

        if locked {
            let label = UILabel(frame: indicator.bounds.insetBy(dx: 2, dy: 2))
            label.text = "LOCKED"
            label.textColor = UIColor.systemYellow
            label.font = UIFont.boldSystemFont(ofSize: 8)
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontSizeToFitWidth = true
            indicator.addSubview(label)
            indicator.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            previewContainer.addSubview(indicator)
            UIView.animate(withDuration: 0.2) {
                indicator.transform = .identity
            }
        } else {
            indicator.alpha = 0
            indicator.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
            previewContainer.addSubview(indicator)
            UIView.animate(withDuration: 0.15) {
                indicator.alpha = 1
                indicator.transform = .identity
            } completion: { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    UIView.animate(withDuration: 0.2) {
                        indicator.alpha = 0
                    } completion: { _ in
                        indicator.removeFromSuperview()
                        if self.focusIndicator === indicator { self.focusIndicator = nil }
                    }
                }
            }
        }
        focusIndicator = indicator
    }

    private func removeFocusIndicator() {
        focusIndicator?.removeFromSuperview()
        focusIndicator = nil
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

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = flashOn ? .on : .off
        settings.photoQualityPrioritization = .speed
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

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor in
                self.finishCapture()
            }
            return
        }

        let preview = Self.generatePreview(from: data)
        DispatchQueue.main.async {
            self.completeCapture(jpeg: data, preview: preview)
        }
    }

    private static func generatePreview(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 120,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
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
