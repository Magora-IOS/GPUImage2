varying highp vec2 textureCoordinate;

uniform sampler2D inputImageTexture;
uniform highp vec2 frameBufferResolution;
uniform highp float fractionalWidthOfPixel;
uniform highp float aspectRatio;
uniform highp vec2 u_Resolution;
uniform highp int blurredCoords[200];

#define X_COUNT 10
#define Y_COUNT 20
#define S (u_Resolution.x / 20.0) // The cell size.


void main()
{
    highp int xIndex  = int(floor(gl_FragCoord.x / (frameBufferResolution / 10.0)));
    highp int yIndex = int(floor(gl_FragCoord.y / (frameBufferResolution / 10.0)));
    highp int index = yIndex * int(X_COUNT) + xIndex;
    
       if (blurredCoords[index] == 1) {
            highp vec2 p = textureCoordinate.xy * u_Resolution.xy;
            gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / S) * S / u_Resolution.xy);
        }else{
            gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
        }
}
