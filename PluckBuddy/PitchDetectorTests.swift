//
//  PitchDetectorTests.swift
//  PluckBuddyTests
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/15.
//

import XCTest
import AVFoundation
@testable import PluckBuddy

/// 音高检测测试
final class PitchDetectorTests: XCTestCase {
    
    /// 检测 A2 (110Hz)
    func testA2Detection() throws {
        let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
        
        // 生成 110Hz 正弦波
        let buffer = generateSineWave(frequency: 110.0, sampleRate: 44100, duration: 0.1)
        
        let detectedFreq = detector.detectPitch(from: buffer)
        
        // 验证检测结果在 108-112Hz 之间（允许 2Hz 误差）
        XCTAssertNotNil(detectedFreq, "应该检测到频率")
        if let freq = detectedFreq {
            XCTAssertGreaterThan(freq, 108.0, "检测到的频率应大于 108Hz，实际: \(freq)")
            XCTAssertLessThan(freq, 112.0, "检测到的频率应小于 112Hz，实际: \(freq)")
        }
    }
    
    /// 检测 d3 (146.83Hz)
    func testD3Detection() throws {
        let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
        
        let buffer = generateSineWave(frequency: 146.83, sampleRate: 44100, duration: 0.1)
        
        let detectedFreq = detector.detectPitch(from: buffer)
        
        XCTAssertNotNil(detectedFreq)
        if let freq = detectedFreq {
            XCTAssertGreaterThan(freq, 144.0, "检测到的频率应大于 144Hz，实际: \(freq)")
            XCTAssertLessThan(freq, 149.0, "检测到的频率应小于 149Hz，实际: \(freq)")
        }
    }
    
    /// 检测 e3 (164.81Hz)
    func testE3Detection() throws {
        let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
        
        let buffer = generateSineWave(frequency: 164.81, sampleRate: 44100, duration: 0.1)
        
        let detectedFreq = detector.detectPitch(from: buffer)
        
        XCTAssertNotNil(detectedFreq)
        if let freq = detectedFreq {
            XCTAssertGreaterThan(freq, 162.0, "检测到的频率应大于 162Hz，实际: \(freq)")
            XCTAssertLessThan(freq, 168.0, "检测到的频率应小于 168Hz，实际: \(freq)")
        }
    }
    
    /// 检测 a3 (220Hz)
    func testA3Detection() throws {
        let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
        
        let buffer = generateSineWave(frequency: 220.0, sampleRate: 44100, duration: 0.1)
        
        let detectedFreq = detector.detectPitch(from: buffer)
        
        XCTAssertNotNil(detectedFreq)
        if let freq = detectedFreq {
            XCTAssertGreaterThan(freq, 218.0, "检测到的频率应大于 218Hz，实际: \(freq)")
            XCTAssertLessThan(freq, 222.0, "检测到的频率应小于 222Hz，实际: \(freq)")
        }
    }
    
    /// 无信号时应返回 nil
    func testNoSignal() throws {
        let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
        
        // 生成静音缓冲区
        let buffer = generateSilence(sampleRate: 44100, duration: 0.1)
        
        let detectedFreq = detector.detectPitch(from: buffer)
        
        XCTAssertNil(detectedFreq, "静音应该返回 nil")
    }
    
    /// 超出范围的频率应返回 nil
    func testOutOfRange() throws {
        let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
        
        // 生成 50Hz（太低）
        let lowBuffer = generateSineWave(frequency: 50.0, sampleRate: 44100, duration: 0.1)
        let lowFreq = detector.detectPitch(from: lowBuffer)
        XCTAssertNil(lowFreq, "50Hz 应该被过滤")
        
        // 生成 400Hz（太高）
        let highBuffer = generateSineWave(frequency: 400.0, sampleRate: 44100, duration: 0.1)
        let highFreq = detector.detectPitch(from: highBuffer)
        XCTAssertNil(highFreq, "400Hz 应该被过滤")
    }
    
    // MARK: - Helper Functions
    
    /// 生成正弦波测试信号
    func generateSineWave(frequency: Double, sampleRate: Double, duration: Double) -> AVAudioPCMBuffer {
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = buffer.frameCapacity
        
        let channelData = buffer.floatChannelData![0]
        let angularFrequency = 2.0 * Double.pi * frequency / sampleRate
        
        for i in 0..<frameCount {
            channelData[i] = Float(sin(angularFrequency * Double(i)))
        }
        
        return buffer
    }
    
    /// 生成静音信号
    func generateSilence(sampleRate: Double, duration: Double) -> AVAudioPCMBuffer {
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = buffer.frameCapacity
        
        let channelData = buffer.floatChannelData![0]
        for i in 0..<frameCount {
            channelData[i] = 0.0
        }
        
        return buffer
    }
}
