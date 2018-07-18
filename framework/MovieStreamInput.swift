import Foundation
import AVFoundation

public protocol MovieStreamInputDelegate: class {
    func didFinishMovie()
}

public class MovieStreamInput: ImageSource {
    public let targets = TargetContainer()
    public var runBenchmark = false
    public weak var delegate: MovieStreamInputDelegate?
    
    public var currentTime:CMTime? {
        get {
            return self.gavPlayer.currentTime()
        }
    }
    let yuvConversionShader:ShaderProgram
    let asset:AVAsset
    let playAtActualSpeed:Bool
    let loop:Bool
    var videoEncodingIsFinished = false
    var previousFrameTime = kCMTimeZero
    var previousActualFrameTime = CFAbsoluteTimeGetCurrent()
    
    var numberOfFramesCaptured = 0
    var totalFrameTimeDuringCapture:Double = 0.0
    var isPlaying = false
    
    public init(asset:AVAsset, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        self.asset = asset
        self.playAtActualSpeed = playAtActualSpeed
        self.loop = loop
        self.yuvConversionShader = crashOnShaderCompileFailure("MovieInput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionFullRangeFragmentShader)}
    }
    
    public convenience init(url:URL, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
        let inputAsset = AVURLAsset(url:url, options:inputOptions)
        try self.init(asset:inputAsset, playAtActualSpeed:playAtActualSpeed, loop:loop)
        self.videoURL = url
    }
    
    // MARK: -
    // MARK: Playback control
    
    var gavPlayer:AVPlayer = AVPlayer()
    var gplayerItem:AVPlayerItem!
    var goutput:AVPlayerItemVideoOutput!
    var videoURL:URL!
    
    public func start(atTime time: CMTime? = nil) {
        let startTime: CMTime = time ?? CMTimeMakeWithSeconds(0, 100)
        
        isPlaying = true
        gplayerItem = AVPlayerItem(url: videoURL)
        
        gavPlayer.replaceCurrentItem(with: gplayerItem)
        if self.gavPlayer.status == .readyToPlay {
            self.gavPlayer.seek(to: startTime) { [unowned self] (completed: Bool) -> Void in
                self.gavPlayer.play()
            }
        }
        self.gavPlayer.play()
        
        
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError? = nil
            let status = self.asset.statusOfValue(forKey: "tracks", error: &error)
            
            switch status {
            case .loaded:
                let settings:Dictionary = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                let output:AVPlayerItemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
                self.gplayerItem.add(output)
                self.goutput = output
                while (self.isPlaying) {
                    self.readNextVideoFrame()
                }
                
                break
            // Sucessfully loaded, continue processing
            default:
                print("Failed to load the tracks")
                break
            }
        }
    }
    
    public func cancel() {
        self.endProcessing()
    }
    
    public func pause() {
        self.endProcessing()
    }
    
    func endProcessing() {
        self.gavPlayer.pause()
        self.isPlaying = false
        self.delegate?.didFinishMovie()
    }
    
    // MARK: -
    // MARK: Internal processing functions
    
    func readNextVideoFrame() {
        if ( !videoEncodingIsFinished) {
            print(self.gplayerItem.currentTime())
            
            
            if let sampleBuffer: CVPixelBuffer = self.goutput.copyPixelBuffer(forItemTime: self.gplayerItem.currentTime(), itemTimeForDisplay: nil) {
                if (playAtActualSpeed) {
                    // Do this outside of the video processing queue to not slow that down while waiting
                    let currentSampleTime = self.gplayerItem.currentTime()
                    let differenceFromLastFrame = CMTimeSubtract(currentSampleTime, previousFrameTime)
                    let currentActualTime = CFAbsoluteTimeGetCurrent()
                    
                    let frameTimeDifference = CMTimeGetSeconds(differenceFromLastFrame)
                    let actualTimeDifference = currentActualTime - previousActualFrameTime
                    
                    if (frameTimeDifference > actualTimeDifference) {
                        //  usleep(UInt32(round(1000000.0 * (frameTimeDifference - actualTimeDifference))))
                    }
                    
                    previousFrameTime = currentSampleTime
                    previousActualFrameTime = CFAbsoluteTimeGetCurrent()
                }
                
                sharedImageProcessingContext.runOperationSynchronously{
                    self.process(movieFrame:sampleBuffer, withSampleTime:self.gplayerItem.currentTime())
                }
            } else {
                if (!loop) {
                    //      videoEncodingIsFinished = true
                    if (videoEncodingIsFinished) {
                        self.endProcessing()
                    }
                }
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
        
        var orientation:ImageOrientation = .portrait
        
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
        /////
        
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

