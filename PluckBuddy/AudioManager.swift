//
//  AudioManager.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/15.
//

import Foundation
import AVFoundation
import Combine

/// 统一管理音频会话和麦克风权限
@MainActor
class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()
    
    @Published var hasPermission = false
    @Published var isListening = false
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Permission
    func requestMicrophonePermission() async -> Bool {
        // 对于 iOS 17+，AVAudioApplication 提供了更现代的 API
        #if canImport(AVFAudio)
        if #available(iOS 17.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            
            switch status {
            case .granted:
                hasPermission = true
                return true
            case .denied, .undetermined:
                // 请求权限
                let granted = await AVAudioApplication.requestRecordPermission()
                hasPermission = granted
                return granted
            @unknown default:
                return false
            }
        } else {
            // iOS 16 及以下使用传统 API
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        self.hasPermission = granted
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
        #else
        // 非 iOS 平台回退
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    self.hasPermission = granted
                    continuation.resume(returning: granted)
                }
            }
        }
        #endif
    }
    
    // MARK: - Audio Session Setup
    func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // ✨ 使用 .playAndRecord 允许同时播放节拍器和录音
        // ✨ 添加 .mixWithOthers 允许与其他音频混合
        // ✨ 添加 .defaultToSpeaker 让声音从扬声器播放
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        // ✨ 设置首选采样率为 48000 Hz（统一采样率）
        try session.setPreferredSampleRate(48000.0)
        try session.setActive(true)
        print("✅ 音频会话已配置为播放+录音模式")
        print("   采样率: \(session.sampleRate) Hz")
    }
    
    // MARK: - Start Listening
    func startListening(onBufferReceived: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        guard hasPermission else {
            throw AudioError.noPermission
        }
        
        try setupAudioSession()
        
        // 初始化 Audio Engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioError.engineInitFailed
        }
        
        inputNode = engine.inputNode
        guard let input = inputNode else {
            throw AudioError.noInputNode
        }
        
        // ✅ 获取实际输入格式和采样率
        let inputFormat = input.outputFormat(forBus: 0)
        let actualSampleRate = inputFormat.sampleRate
        
        // ✅ 打印实际采样率用于调试
        print("🎤 实际采样率: \(actualSampleRate) Hz")
        
        // 安装 tap（每次接收 4096 个采样点）
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, time in
            onBufferReceived(buffer, time)
        }
        
        // 启动引擎
        try engine.start()
        isListening = true
    }
    
    // MARK: - Stop Listening
    func stopListening() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isListening = false
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    // MARK: - Error Types
    enum AudioError: LocalizedError {
        case noPermission
        case engineInitFailed
        case noInputNode
        
        var errorDescription: String? {
            switch self {
            case .noPermission:
                return L("需要麦克风权限才能进行音高检测")
            case .engineInitFailed:
                return L("音频引擎初始化失败")
            case .noInputNode:
                return L("无法访问音频输入节点")
            }
        }
    }
}
