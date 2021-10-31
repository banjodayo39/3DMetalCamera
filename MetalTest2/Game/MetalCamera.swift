//
//  MetalCamera.swift
//  MetalTest2
//
//  Created by Dayo Banjo on 10/30/21.
//
//
//  MetalCamera2.swift
//  DropDart
//
//  Created by Dayo Banjo on 10/15/21.
//

import AVFoundation


import MetalKit

enum MetalCameraError: Error {
    case noVideoDevice
    case noAudioDevice
    case deviceInputInitialize
}

public class MetalCamera2: NSObject, OperationChain, AudioOperationChain {
    public static let libraryName = "Metal Camera"
    public var runBenchmark = false
    public var logFPS = false
    
    public let captureSession: AVCaptureSession
    public var inputCamera: AVCaptureDevice!
    
    var videoInput: AVCaptureDeviceInput!
    let videoOutput: AVCaptureVideoDataOutput!
    var videoTextureCache: CVMetalTextureCache?
    
    var audioInput: AVCaptureDeviceInput?
    var audioOutput: AVCaptureAudioDataOutput?
    
    let cameraProcessingQueue = DispatchQueue.global()
    let cameraFrameProcessingQueue = DispatchQueue(label: "MetalCamera.cameraFrameProcessingQueue", attributes: [])
    
    let frameRenderingSemaphore = DispatchSemaphore(value: 1)
    
    var numberOfFramesCaptured = 0
    var totalFrameTimeDuringCapture: Double = 0.0
    var framesSinceLastCheck = 0
    var lastCheckTime = CFAbsoluteTimeGetCurrent()
    
    public let sourceKey: String
    public var targets = TargetContainer<OperationChain>()
    public var audioTargets = TargetContainer<AudioOperationChain>()
    
    let useMic: Bool
    var currentPosition = AVCaptureDevice.Position.front
    var videoOrientation: AVCaptureVideoOrientation?
    var isVideoMirrored: Bool?
    
    var device : MTLDevice!
    
    public init(sessionPreset: AVCaptureSession.Preset = .hd1280x720,
                position: AVCaptureDevice.Position = .front,
                sourceKey: String = "camera",
                useMic: Bool = false,
                videoOrientation: AVCaptureVideoOrientation? = .portrait,
                isVideoMirrored: Bool? = nil) throws {
        self.sourceKey = sourceKey
        self.useMic = useMic
        
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                     kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        self.videoOrientation = videoOrientation
        self.isVideoMirrored = isVideoMirrored
     
        super.init()
        
        defer {
            captureSession.commitConfiguration()
        }
        
        guard let d = MTLCreateSystemDefaultDevice() else{
            return
        }
        device = d
        
        try updateVideoInput(position: position)
        
        if useMic {
            guard let audio = AVCaptureDevice.default(for: .audio),
                  let audioInput = try? AVCaptureDeviceInput(device: audio) else {
                throw MetalCameraError.noAudioDevice
            }
            
            let audioDataOutput = AVCaptureAudioDataOutput()
            
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
            
            if captureSession.canAddOutput(audioDataOutput) {
                captureSession.addOutput(audioDataOutput)
            }
            
            self.audioInput = audioInput
            self.audioOutput = audioDataOutput
        }
        
        captureSession.sessionPreset = sessionPreset
        captureSession.commitConfiguration()
        
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &videoTextureCache)
        
        videoOutput.setSampleBufferDelegate(self, queue: cameraProcessingQueue)
        audioOutput?.setSampleBufferDelegate(self, queue: cameraProcessingQueue)
    }
    
    deinit {
        cameraFrameProcessingQueue.sync {
            stopCapture()
            videoOutput?.setSampleBufferDelegate(nil, queue:nil)
        }
    }
    
    public func startCapture() {
        guard captureSession.isRunning == false else { return }
        
        let _ = frameRenderingSemaphore.wait(timeout:DispatchTime.distantFuture)
        numberOfFramesCaptured = 0
        totalFrameTimeDuringCapture = 0
        frameRenderingSemaphore.signal()
        
        captureSession.startRunning()
    }
    
    public func stopCapture() {
        guard captureSession.isRunning else { return }
        
        let _ = frameRenderingSemaphore.wait(timeout:DispatchTime.distantFuture)
        captureSession.stopRunning()
        self.frameRenderingSemaphore.signal()
    }
    
    private func updateVideoInput(position: AVCaptureDevice.Position) throws {
        guard let device = position.device() else {
            throw MetalCameraError.noVideoDevice
        }
        
        inputCamera = device
        
        if videoInput != nil {
            captureSession.removeInput(videoInput)
        }
        
        do {
            self.videoInput = try AVCaptureDeviceInput(device: inputCamera)
        } catch {
            throw MetalCameraError.deviceInputInitialize
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        }
        
        if let orientation = videoOrientation {
            videoOutput.connection(with: .video)?.videoOrientation = orientation
        }
        
        if let isVideoMirrored = isVideoMirrored, position == .front {
            videoOutput.connection(with: .video)?.isVideoMirrored = isVideoMirrored
        }
        
        currentPosition = position
    }
    
    public func switchPosition() throws {
        captureSession.beginConfiguration()
        try updateVideoInput(position: currentPosition == .front ? .back : .front)
        captureSession.commitConfiguration()
    }
    
    func toggleTorch() {
        //  guard let device = AVCaptureDevice.default(for: .video) else { return }
        
        if inputCamera.hasTorch {
            do {
                try inputCamera.lockForConfiguration()
                
                inputCamera.torchMode = inputCamera.torchMode == .on ? .off : .on
                
                inputCamera.unlockForConfiguration()
            } catch {
                print("Torch could not be used")
            }
        } else {
            print("Torch is not available")
        }
    }
    
    public func newTextureAvailable(_ texture: Texture) {}
    public func newAudioAvailable(_ sampleBuffer: AudioBuffer) {}
}

extension MetalCamera2: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if connection == videoOutput?.connection(with: .video) {
            for target in targets {
                if let target = target as? CMSampleChain {
                    target.newBufferAvailable(sampleBuffer)
                }
            }
            
            handleVideo(sampleBuffer)
            
        } else if connection == audioOutput?.connection(with: .audio) {
            handleAudio(sampleBuffer)
        }
    }
    
    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard (frameRenderingSemaphore.wait(timeout:DispatchTime.now()) == DispatchTimeoutResult.success) else { return }
        guard let cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let videoTextureCache = videoTextureCache else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let bufferWidth = CVPixelBufferGetWidth(cameraFrame)
        let bufferHeight = CVPixelBufferGetHeight(cameraFrame)
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        CVPixelBufferLockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        cameraFrameProcessingQueue.async {
            CVPixelBufferUnlockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
            
            let texture: Texture?
            
            var textureRef: CVMetalTexture? = nil
            let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, videoTextureCache, cameraFrame, nil, .bgra8Unorm, bufferWidth, bufferHeight, 0, &textureRef)
            if let concreteTexture = textureRef,
               let cameraTexture = CVMetalTextureGetTexture(concreteTexture) {
                
                let samplerDescriptor = MTLSamplerDescriptor()
                samplerDescriptor.normalizedCoordinates = true
                samplerDescriptor.minFilter = .linear
                samplerDescriptor.magFilter = .linear
                samplerDescriptor.mipFilter = .linear
                guard let sampler = self.device.makeSamplerState(descriptor: samplerDescriptor) else {
                    return
                }
                
                texture = Texture(mtlTexture:cameraTexture, samplerState: sampler)
            } else {
                texture = nil
            }
            
            if let texture = texture {
                self.operationFinished(texture)
            }
            
            if self.runBenchmark {
                self.numberOfFramesCaptured += 1
                
                let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
                self.totalFrameTimeDuringCapture += currentFrameTime
                debugPrint("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms")
                debugPrint("Current frame time : \(1000.0 * currentFrameTime) ms")
            }
            
            if self.logFPS {
                if ((CFAbsoluteTimeGetCurrent() - self.lastCheckTime) > 1.0) {
                    self.lastCheckTime = CFAbsoluteTimeGetCurrent()
                    debugPrint("FPS: \(self.framesSinceLastCheck)")
                    self.framesSinceLastCheck = 0
                }
                self.framesSinceLastCheck += 1
            }
            
            self.frameRenderingSemaphore.signal()
        }
    }
    
    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        //audioOperationFinished(AudioBuffer(sampleBuffer, sourceKey))
    }
}



extension AVCaptureDevice.Position {
    func device() -> AVCaptureDevice? {
        let deviceDescoverySession = AVCaptureDevice.DiscoverySession.init(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                           mediaType: .video,
                                                                           position: self)
        
        for device in deviceDescoverySession.devices where device.position == self {
            return device
        }
        
        return nil
    }
}
