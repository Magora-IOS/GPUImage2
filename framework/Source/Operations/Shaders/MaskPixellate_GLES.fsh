varying highp vec2 textureCoordinate;

uniform sampler2D inputImageTexture;

uniform highp float fractionalWidthOfPixel;
uniform highp float aspectRatio;
uniform highp vec2 u_Resolution;
uniform highp int blurredCoords[200];

#define X_COUNT 10
#define Y_COUNT 20
#define S (u_Resolution.x / 20.0) // The cell size.


void main()
{
    highp vec2 sampleDivisor = vec2(fractionalWidthOfPixel, fractionalWidthOfPixel / aspectRatio);
    highp vec2 samplePos = textureCoordinate - mod(textureCoordinate, sampleDivisor) + 0.5 * sampleDivisor;
    
    highp int xIndex  = int(floor(gl_FragCoord.x / fractionalWidthOfPixel));
    highp int yIndex = int(floor((u_Resolution.y - gl_FragCoord.y) / fractionalWidthOfPixel));
    highp int index = yIndex * int(X_COUNT) + xIndex;
    
    
 //   if (blurredCoords[index] == 1) {
            highp vec2 p = textureCoordinate.xy * u_Resolution.yx;
            gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / S) * S / u_Resolution.yx);
  //      }else{
  //          gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
  //      }
    
}

