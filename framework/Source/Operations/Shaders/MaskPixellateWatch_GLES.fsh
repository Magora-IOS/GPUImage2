varying highp vec2 textureCoordinate;
uniform sampler2D inputImageTexture;
uniform highp vec2 frameBufferResolution;
uniform highp int blurredCoords[200];
#define X_COUNT 10
#define Y_COUNT 20
#define X_COORD gl_FragCoord.x
#define Y_COORD gl_FragCoord.y
#define S (frameBufferResolution.x / 20.0) // The cell size.
void main()
{
    highp int xIndex  = int(floor(X_COORD / (frameBufferResolution.x / 10.0)));
    highp int yIndex = int(floor(Y_COORD / (frameBufferResolution.x / 10.0)));
    highp int index = yIndex * int(X_COUNT) + xIndex;
    if (blurredCoords[index] == 1) {
        highp vec2 p = textureCoordinate.xy * frameBufferResolution.xy;
        gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / S) * S / frameBufferResolution.xy);
    }else{
        gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
        }
}
