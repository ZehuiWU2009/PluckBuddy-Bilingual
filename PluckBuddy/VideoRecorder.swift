//
//  VideoRecorder.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/19.
//
//  视频录制管理器
//

import AVFoundation
import UIKit
import Combine

@MainActor
class VideoRecorder: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var isAuthorized = false
    
    // MARK: - Private Properties
    private let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureMovieFileOutput?
    private var currentRecordingURL: URL?
    
    // MARK: - Public Properties
    var previewLayer: AVCaptureVideoPreviewLayer {
        AVCaptureVideoPreviewLayer(session: captureSession)
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        Task {
            await checkAuthorization()
        }
    }
    
    // MARK: - Authorization
    func checkAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            try? setupCamera()
            
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            if isAuthorized {
                try? setupCamera()
            }
            
        default:
            isAuthorized = false
        }
    }
    
    // MARK: - Camera Setup
    private func setupCamera() throws {
        captureSession.beginConfiguration()
        
        // 1. 设置分辨率
        captureSession.sessionPreset = .high
        
        // 2. 添加前置摄像头输入
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw VideoRecorderError.cameraNotAvailable
        }
        
        let videoInput = try AVCaptureDeviceInput(device: frontCamera)
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        // 3. 添加音频输入（录制声音）
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            let audioInput = try? AVCaptureDeviceInput(device: audioDevice)
            if let audioInput = audioInput, captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
        }
        
        // 4. 添加视频输出
        let output = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoOutput = output
        }
        
        captureSession.commitConfiguration()
        
        // 5. 启动会话
        Task {
            captureSession.startRunning()
        }
    }
    
    // MARK: - Recording Control
    func startRecording() {
        guard let videoOutput = videoOutput, !isRecording else { return }
        
        // 生成临时文件路径
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("practice_\(Date().timeIntervalSince1970).mp4")
        
        currentRecordingURL = outputURL
        
        // 开始录制
        videoOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
    }
    
    func stopRecording() {
        guard let videoOutput = videoOutput, isRecording else { return }
        
        videoOutput.stopRecording()
        isRecording = false
    }
    
    // MARK: - Cleanup
    func cleanup() {
        captureSession.stopRunning()
    }
    
    nonisolated deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("📹 开始录制: \(fileURL)")
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        if let error = error {
            print("❌ 录制失败: \(error.localizedDescription)")
            return
        }
        
        print("✅ 录制完成: \(outputFileURL)")
        
        // 保存到相册（需要权限）
        Task { @MainActor in
            await saveToPhotoLibrary(url: outputFileURL)
        }
    }
    
    @MainActor
    private func saveToPhotoLibrary(url: URL) async {
        // TODO: 实现保存到相册功能
        // 需要在 Info.plist 中添加 NSPhotoLibraryAddUsageDescription
        print("💾 视频已保存: \(url.path)")
    }
}

// MARK: - Error
enum VideoRecorderError: Error {
    case cameraNotAvailable
    case unauthorized
    case setupFailed
}
