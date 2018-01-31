public class MaskPixellate: BasicOperation {
    public var fractionalWidthOfAPixel:Float = 1.0 {
        didSet {
            let imageWidth = 1.0 / Float(self.renderFramebuffer?.size.width ?? 2048)
            uniformSettings["fractionalWidthOfPixel"] = max(fractionalWidthOfAPixel, imageWidth)
        }
    }
    
    public var u_Resolution:Size = Size(width:100, height:100) {
//        didSet {
//             uniformSettings["u_Resolution"] = u_Resolution
//        }
    }
    
    public var blurredCoords: [Int] = [] {
        didSet {
            uniformSettings["blurredCoords"] = blurredCoords
        }
    }
    
    public init(resolution:Size, pixelMask:[Int]) {
        super.init(fragmentShader:MaskPixellateFragmentShader, numberOfInputs:1)
        if pixelMask.count != 200 {
            let array = Array(repeating: 1, count: 200)
            ({blurredCoords = array})()
        } else {
            ({blurredCoords = pixelMask})()
        }
        
        ({u_Resolution = resolution})()
        ({fractionalWidthOfAPixel = resolution.width / 10.0})()
    }
    
    public func changeMask(pixelMask:[Int]) {
        if pixelMask.count != 200 {
            let array = Array(repeating: 1, count: 200)
            ({blurredCoords = array})()
        } else {
            ({blurredCoords = pixelMask})()
        }
        
        ({fractionalWidthOfAPixel = u_Resolution.width / 10.0})()
    }
}
