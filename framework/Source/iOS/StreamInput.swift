import AVFoundation

public class StreamInput: ImageSource {
    public let targets = TargetContainer()
    public var runBenchmark = false
    
    let yuvConversionShader:ShaderProgram
    let asset:AVAsset
    let playAtActualSpeed:Bool
    let loop:Bool
    var videoEncodingIsFinished = false
    var previousFrameTime = kCMTimeZero
    var previousActualFrameTime = CFAbsoluteTimeGetCurrent()
    
    var numberOfFramesCaptured = 0
    var totalFrameTimeDuringCapture:Double = 0.0
    
    // TODO: Add movie reader synchronization
    // TODO: Someone will have to add back in the AVPlayerItem logic, because I don't know how that works
    public init(asset:AVAsset, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        self.asset = asset
        self.playAtActualSpeed = playAtActualSpeed
        self.loop = loop
        self.yuvConversionShader = crashOnShaderCompileFailure("MovieInput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionFullRangeFragmentShader)}
        
       // assetReader = try AVAssetReader(asset:self.asset)
        
      //  let outputSettings:[String:AnyObject] = [(kCVPixelBufferPixelFormatTypeKey as String):NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))]
      //  let readerVideoTrackOutput = AVAssetReaderTrackOutput(track:self.asset.tracks(withMediaType: AVMediaTypeVideo)[0], outputSettings:outputSettings)
      //  readerVideoTrackOutput.alwaysCopiesSampleData = false
      //  assetReader.add(readerVideoTrackOutput)
        // TODO: Audio here
    }
    
    public convenience init(url:URL, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
        let inputAsset = AVURLAsset(url:url, options:inputOptions)
        try self.init(asset:inputAsset, playAtActualSpeed:playAtActualSpeed, loop:loop)
    }
    
    // MARK: -
    // MARK: Playback control
    
    var gavPlayer:AVPlayer!
    var gplayerItem:AVPlayerItem!
    var goutput:AVPlayerItemVideoOutput!
    
    public func start() {
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError? = nil
            let status = self.asset.statusOfValue(forKey: "tracks", error: &error)
            
            switch status {
            case .loaded:
                let settings:Dictionary = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                let output:AVPlayerItemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
                let playerItem:AVPlayerItem = AVPlayerItem(asset: self.asset)
                playerItem.add(output)
                let avPlayer:AVPlayer = AVPlayer(playerItem: playerItem)
                self.gavPlayer = avPlayer
                self.gplayerItem = playerItem
                self.goutput = output
//                self.startAvPlayerStream()
                
                while (true) {
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
        //assetReader.cancelReading()
        self.endProcessing()
    }
    
    func endProcessing() {
        
    }
    
    // MARK: -
    // MARK: Internal processing functions
    
    func readNextVideoFrame() {
        if ( !videoEncodingIsFinished) {
            if let sampleBuffer: CVPixelBuffer = self.goutput.copyPixelBuffer(forItemTime: self.gplayerItem.currentTime(), itemTimeForDisplay: nil) {
          //  if let sampleBuffer = videoTrackOutput.copyNextSampleBuffer() {
                if (playAtActualSpeed) {
                    // Do this outside of the video processing queue to not slow that down while waiting
                    let currentSampleTime = self.gplayerItem.currentTime()
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
                    self.process(movieFrame:sampleBuffer, withSampleTime:self.gplayerItem.currentTime())
                }
            } else {
                if (!loop) {
                    videoEncodingIsFinished = true
                    if (videoEncodingIsFinished) {
                        self.endProcessing()
                    }
                }
            }
        }
        //        else if (synchronizedMovieWriter != nil) {
        //            if (assetReader.status == .Completed) {
        //                self.endProcessing()
        //            }
        //        }
        
    }
    
//    func process(movieFrame frame:CMSampleBuffer) {
//        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(frame)
//        let movieFrame = CMSampleBufferGetImageBuffer(frame)!
//
//        //        processingFrameTime = currentSampleTime
//        self.process(movieFrame:movieFrame, withSampleTime:currentSampleTime)
//    }
    
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
        
        let luminanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
        luminanceFramebuffer.lock()
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceFramebuffer.texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), 0, GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(movieFrame, 0))
        
        let chrominanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
        chrominanceFramebuffer.lock()
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceFramebuffer.texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), 0, GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(movieFrame, 1))
        
        let movieFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:false)
        
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
