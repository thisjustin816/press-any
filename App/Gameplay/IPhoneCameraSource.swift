import AVFoundation
import EmulationCore
import Foundation

@MainActor
final class IPhoneCameraSource: GameplayCameraSource {
    private let worker = IPhoneCameraWorker()

    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(
        position: GameplayCameraPosition, rotationAngle: Double,
        receive: @escaping @Sendable (CameraFrame) -> Void,
        failure: @escaping @Sendable () -> Void
    ) {
        worker.start(position: position, rotationAngle: rotationAngle, receive: receive, failure: failure)
    }

    func stop() { worker.stop() }

    deinit { worker.stop() }
}

/// Session configuration, blocking start/stop, and sample conversion all stay on this queue.
private final class IPhoneCameraWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Gameplay.Camera", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var receive: (@Sendable (CameraFrame) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start(
        position: GameplayCameraPosition, rotationAngle: Double,
        receive: @escaping @Sendable (CameraFrame) -> Void,
        failure: @escaping @Sendable () -> Void
    ) {
        queue.async { [self] in
            stopOnQueue()
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: position == .front ? .front : .back
                  ), let input = try? AVCaptureDeviceInput(device: device) else {
                failure()
                return
            }
            let session = AVCaptureSession()
            session.automaticallyConfiguresApplicationAudioSession = false
            session.beginConfiguration()
            session.sessionPreset = .medium
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                failure()
                return
            }
            session.addInput(input)
            session.addOutput(output)
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = position == .front
                }
            }
            output.setSampleBufferDelegate(self, queue: queue)
            session.commitConfiguration()
            self.session = session
            self.output = output
            self.receive = receive
            for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { _ in
                    failure()
                })
            }
            session.startRunning()
            if !session.isRunning { failure() }
        }
    }

    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        output?.setSampleBufferDelegate(nil, queue: nil)
        session?.stopRunning()
        output = nil
        session = nil
        receive = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === self.output, session?.isRunning == true,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { return }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        if let frame = try? CameraFrameSampler.sampleBGRA(
            UnsafeRawBufferPointer(start: base, count: stride * height),
            width: width, height: height, bytesPerRow: stride
        ) {
            receive?(frame)
        }
    }
}
