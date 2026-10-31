//
//  CameraManager.swift
//  PluckBuddy
//
//  Created by Zehui Wu on 2026/8/17.
//

import AVFoundation
import UIKit
import Combine

/// 相机管理器
/// 负责管理摄像头会话和视频帧捕获
@MainActor
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    @Published var isAuthorized = false
    @Published var setupResult: SessionSetupResult = .success
    
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    /// 视频帧回调
    var onFrameCapture: ((CVPixelBuffer) -> Void)?
    
    enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    /// 检查相机权限
    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                Task { @MainActor in
                    self.isAuthorized = granted
                    self.sessionQueue.resume()
                }
            }
            
        default:
            isAuthorized = false
            setupResult = .notAuthorized
        }
    }
    
    // MARK: - Session Management
    
    /// 配置相机会话
    func configureSession() {
        guard setupResult == .success else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            
            // 设置会话预设（高质量）
            self.session.sessionPreset = .high
            
            // 添加视频输入
            do {
                let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                guard let device = videoDevice else {
                    Task { @MainActor in
                        self.setupResult = .configurationFailed
                    }
                    self.session.commitConfiguration()
                    return
                }
                
                let videoDeviceInput = try AVCaptureDeviceInput(device: device)
                
                if self.session.canAddInput(videoDeviceInput) {
                    self.session.addInput(videoDeviceInput)
                    self.videoDeviceInput = videoDeviceInput
                } else {
                    Task { @MainActor in
                        self.setupResult = .configurationFailed
                    }
                    self.session.commitConfiguration()
                    return
                }
            } catch {
                Task { @MainActor in
                    self.setupResult = .configurationFailed
                }
                self.session.commitConfiguration()
                return
            }
            
            // 添加视频输出
            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
                
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                ]
                
                self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.data.output.queue"))
                
                // 设置视频方向。iOS 17 起 videoOrientation 已废弃，改用 videoRotationAngle；
                // 竖屏对应 90°，与原 .portrait 等价
                if let connection = self.videoDataOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90.0) {
                        connection.videoRotationAngle = 90.0
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true  // 前置摄像头镜像
                    }
                }
            } else {
                Task { @MainActor in
                    self.setupResult = .configurationFailed
                }
                self.session.commitConfiguration()
                return
            }
            
            self.session.commitConfiguration()
        }
    }
    
    /// 开始会话
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            switch self.setupResult {
            case .success:
                self.session.startRunning()
                
            case .notAuthorized:
                print("Camera not authorized")
                
            case .configurationFailed:
                print("Camera configuration failed")
            }
        }
    }
    
    /// 停止会话
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // 回调到主线程
        Task { @MainActor in
            self.onFrameCapture?(pixelBuffer)
        }
    }
}
