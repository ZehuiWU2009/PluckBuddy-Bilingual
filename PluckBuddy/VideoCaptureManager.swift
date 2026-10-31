//
//  VideoCaptureManager.swift
//  PluckBuddy
//
//  Created by Zehui Wu on 2026/7/29.
//

import Foundation
import AVFoundation
import UIKit

/// 视频捕获管理器 - 使用 AVFoundation 捕获摄像头画面
class VideoCaptureManager: NSObject {
    
    // MARK: - Properties
    
    /// 捕获会话
    private let captureSession = AVCaptureSession()
    
    /// 视频输出
    private let videoOutput = AVCaptureVideoDataOutput()
    
    /// 处理队列
    private let videoQueue = DispatchQueue(label: "com.pluckbuddy.video", qos: .userInitiated)
    
    /// 预览图层
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// 帧回调
    var onFrameCaptured: ((CVPixelBuffer) -> Void)?
    
    /// 是否正在运行
    private(set) var isRunning = false
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        print("📹 初始化 VideoCaptureManager")
    }
    
    // MARK: - Setup
    
    /// 配置捕获会话
    func setupCamera() throws {
        print("🎥 开始配置摄像头...")
        
        // 1. 设置会话质量
        captureSession.sessionPreset = .medium  // 640x480，适合手部检测
        
        // 2. 获取前置摄像头
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front  // 前置摄像头
        ) else {
            print("❌ 无法获取前置摄像头")
            throw CaptureError.cameraNotAvailable
        }
        
        print("✅ 找到前置摄像头: \(camera.localizedName)")
        
        // 3. 创建输入
        let input = try AVCaptureDeviceInput(device: camera)
        
        guard captureSession.canAddInput(input) else {
            print("❌ 无法添加摄像头输入")
            throw CaptureError.cannotAddInput
        }
        
        captureSession.addInput(input)
        print("✅ 已添加摄像头输入")
        
        // 4. 配置输出
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        // 丢弃延迟的帧，保证实时性
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        guard captureSession.canAddOutput(videoOutput) else {
            print("❌ 无法添加视频输出")
            throw CaptureError.cannotAddOutput
        }
        
        captureSession.addOutput(videoOutput)
        print("✅ 已添加视频输出")
        
        // 5. 设置视频方向
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            
            // 前置摄像头镜像
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        // 6. 创建预览图层
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        
        print("✅ 摄像头配置完成")
    }
    
    // MARK: - Control
    
    /// 开始捕获
    func startCapture() throws {
        guard !isRunning else {
            print("⚠️ 摄像头已在运行中")
            return
        }
        
        // 如果还未配置，先配置
        if captureSession.inputs.isEmpty {
            try setupCamera()
        }
        
        print("▶️ 启动摄像头捕获...")
        
        // 在后台线程启动
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            
            DispatchQueue.main.async {
                self?.isRunning = true
                print("✅ 摄像头已启动")
            }
        }
    }
    
    /// 停止捕获
    func stopCapture() {
        guard isRunning else {
            print("⚠️ 摄像头未运行")
            return
        }
        
        print("⏹️ 停止摄像头捕获...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            
            DispatchQueue.main.async {
                self?.isRunning = false
                print("✅ 摄像头已停止")
            }
        }
    }
    
    // MARK: - Errors
    
    enum CaptureError: Error, LocalizedError {
        case cameraNotAvailable
        case cannotAddInput
        case cannotAddOutput
        
        var errorDescription: String? {
            switch self {
            case .cameraNotAvailable:
                return L("摄像头不可用")
            case .cannotAddInput:
                return L("无法添加摄像头输入")
            case .cannotAddOutput:
                return L("无法添加视频输出")
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VideoCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 提取像素缓冲区
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // 回调到主线程
        DispatchQueue.main.async { [weak self] in
            self?.onFrameCaptured?(pixelBuffer)
        }
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 帧被丢弃（性能监控）
        // print("⚠️ 丢弃了一帧")
    }
}
