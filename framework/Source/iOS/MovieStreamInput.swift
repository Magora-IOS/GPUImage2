import Foundation
import AVFoundation

public protocol MovieStreamInputDelegate: class {
    func didFinishMovie()
}

public class MovieStreamInput: ImageSource {
    public let targets = TargetContainer()
    public var runBenchmark = false
    public weak var delegate: MovieStreamInputDelegate?
    public private(set) var gavPlayer:AVPlayer = AVPlayer()
    
    public var currentTime:CMTime? {
        return self.gavPlayer.currentTime()
    }
    
    public var duration:CMTime? {
        return self.gavPlayer.currentItem?.duration
    }
    
    public var isPlaybackLikelyToKeepUp: Bool? {
        return self.gavPlayer.currentItem?.isPlaybackLikelyToKeepUp
    }
    
    
    let yuvConversionShader:ShaderProgram
    let asset:AVAsset
    let playAtActualSpeed:Bool
    let loop:Bool
    
    var previousFrameTime = kCMTimeZero
    var previousActualFrameTime = CFAbsoluteTimeGetCurrent()
    
    var numberOfFramesCaptured = 0
    var totalFrameTimeDuringCapture:Double = 0.0
    
    
    // MARK: -
    // MARK: Playback control
    
    var isPlaying = false
    var gplayerItem:AVPlayerItem!
    var goutput:AVPlayerItemVideoOutput!
    
    public init(asset:AVAsset, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        self.asset = asset
        self.playAtActualSpeed = playAtActualSpeed
        self.loop = loop
        self.yuvConversionShader = crashOnShaderCompileFailure("MovieInput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionFullRangeFragmentShader)}
        self.gplayerItem = AVPlayerItem(asset: asset)
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying(notification:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.gavPlayer.currentItem)
    }
    
    public convenience init(url:URL, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
        let inputAsset = AVURLAsset(url:url, options:inputOptions)
        try self.init(asset:inputAsset, playAtActualSpeed:playAtActualSpeed, loop:loop)
        self.gplayerItem = AVPlayerItem(url: url)
        //Set maximum seek accurancy
        self.gplayerItem.seek(to: kCMTimeZero, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
        self.gavPlayer.replaceCurrentItem(with: self.gplayerItem)
    }
    
    @objc
    func playerDidFinishPlaying(notification: NSNotification) {
        self.isPlaying = false
        self.delegate?.didFinishMovie()
        print("playerDidFinishPlaying")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func start(atTime startTime: CMTime? = nil) {
        if self.isPlaying {
            self.gplayerItem.cancelPendingSeeks()
            self.asset.cancelLoading()
        }
        
        
        let playBlock = {
            self.asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
                var error: NSError? = nil
                let status = self.asset.statusOfValue(forKey: "tracks", error: &error)
                
                switch status {
                case .loaded:
                    let settings:Dictionary = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                    let output:AVPlayerItemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
                    self.gplayerItem.add(output)
                    self.goutput = output
                    self.isPlaying = true
                    
                    self.beginProcessing()
                    self.gavPlayer.play()
                    break
                // Sucessfully loaded, continue processing
                default:
                    print("Failed to load the tracks")
                    break
                }
            }
        }
        
        if let startTime = startTime {
            self.gavPlayer.seek(to: startTime, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero) { (isSuccess) in
                playBlock()
            }
        } else {
            playBlock()
        }
        
    }
    
    public func pause() {
        self.gavPlayer.pause()
        self.isPlaying = false
    }
    
    public func seek(to time: CMTime, completion: @escaping (Bool) -> ()) {
        self.gavPlayer.seek(to: time, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: completion)
    }
    
    // MARK: -
    // MARK: Internal processing functions
    
    func beginProcessing() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            while (self?.isPlaying ?? false) {
                guard self?.gplayerItem.status == .readyToPlay else {
                    continue
                }
                
                if let currentTime = self?.gplayerItem.currentTime() {
                    if self?.goutput.hasNewPixelBuffer(forItemTime: currentTime) ?? false {
                        self?.readNextVideoFrame(forItemTime: currentTime)
                    }
                }
            }
        }
    }
    
    func readNextVideoFrame(forItemTime currentSampleTime: CMTime) {
        
        //sampleBuffer could be nil while loading from the network
        if let sampleBuffer: CVPixelBuffer = self.goutput.copyPixelBuffer(forItemTime: currentSampleTime, itemTimeForDisplay: nil) {
            if (playAtActualSpeed) {
                // Do this outside of the video processing queue to not slow that down while waiting
                let differenceFromLastFrame = CMTimeSubtract(currentSampleTime, previousFrameTime)
                let currentActualTime = CFAbsoluteTimeGetCurrent()
                
                let frameTimeDifference = CMTimeGetSeconds(differenceFromLastFrame)
                let actualTimeDifference = currentActualTime - previousActualFrameTime
                
                if (frameTimeDifference > actualTimeDifference) {
                    usleep(UInt32(round(1000000.0 * (frameTimeDifference - actualTimeDifference))))
                }
                
                previousFrameTime = currentSampleTime
                previousActualFrameTime = CFAbsoluteTimeGetCurrent()
            }
            
            sharedImageProcessingContext.runOperationSynchronously{
                self.process(movieFrame:sampleBuffer, withSampleTime: currentSampleTime)
            }
        }
    }
    
    func process(movieFrame:CVPixelBuffer, withSampleTime:CMTime) {
        let bufferHeight = CVPixelBufferGetHeight(movieFrame)
        let bufferWidth = CVPixelBufferGetWidth(movieFrame)
        CVPixelBufferLockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        let conversionMatrix = colorConversionMatrix601FullRangeDefault
        // TODO: Get this color query working
        //        if let colorAttachments = CVBufferGetAttachment(movieFrame, kCVImageBufferYCbCrMatrixKey, nil) {
        //            if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == .EqualTo) {
        //                _preferredConversion = kColorConversion601FullRange
        //            } else {
        //                _preferredConversion = kColorConversion709
        //            }
        //        } else {
        //            _preferredConversion = kColorConversion601FullRange
        //        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        
        var luminanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE0))
        
        let luminanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, movieFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), 0, &luminanceGLTexture)
        
        assert(luminanceGLTextureResult == kCVReturnSuccess && luminanceGLTexture != nil)
        
        let luminanceTexture = CVOpenGLESTextureGetName(luminanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let orientation:ImageOrientation = .portrait
        
        let luminanceFramebuffer: Framebuffer
        do {
            luminanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext, orientation: orientation, size: GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly: true, overriddenTexture: luminanceTexture)
        } catch {
            fatalError("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
        }
        
        luminanceFramebuffer.cache = sharedImageProcessingContext.framebufferCache
        luminanceFramebuffer.lock()
        
        
        var chrominanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        
        let chrominanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, movieFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), 1, &chrominanceGLTexture)
        
        assert(chrominanceGLTextureResult == kCVReturnSuccess && chrominanceGLTexture != nil)
        
        let chrominanceTexture = CVOpenGLESTextureGetName(chrominanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let chrominanceFramebuffer: Framebuffer
        do {
            chrominanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext, orientation: orientation, size: GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly: true, overriddenTexture: chrominanceTexture)
        } catch {
            fatalError("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
        }
        
        chrominanceFramebuffer.cache = sharedImageProcessingContext.framebufferCache
        chrominanceFramebuffer.lock()
        
        let movieFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:orientation, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:false)
        
        convertYUVToRGB(shader:self.yuvConversionShader, luminanceFramebuffer:luminanceFramebuffer, chrominanceFramebuffer:chrominanceFramebuffer, resultFramebuffer:movieFramebuffer, colorConversionMatrix:conversionMatrix)
        CVPixelBufferUnlockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        movieFramebuffer.timingStyle = .videoFrame(timestamp:Timestamp(withSampleTime))
        self.updateTargetsWithFramebuffer(movieFramebuffer)
        
        if self.runBenchmark {
            let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
            self.numberOfFramesCaptured += 1
            self.totalFrameTimeDuringCapture += currentFrameTime
            print("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms")
            print("Current frame time : \(1000.0 * currentFrameTime) ms")
        }
    }
    
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        // Not needed for movie inputs
    }
}

