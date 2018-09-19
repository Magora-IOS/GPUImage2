varying highp vec2 textureCoordinate;
uniform highp vec2 frameBufferResolution;
uniform sampler2D inputImageTexture;
uniform highp int blurredCoords[200];
uniform highp int portrait;
uniform highp int cellsInWidth;
#define X_COUNT 10
#define Y_COUNT 20
#define X_COORD gl_FragCoord.y
#define Y_COORD (frameBufferResolution.y - gl_FragCoord.x)
#define S (frameBufferResolution.x / float(cellsInWidth)) // The cell size.
void main()
{
    //vertical
    if ( frameBufferResolution.y > frameBufferResolution.x ) {
        highp int xIndex  = int(floor(X_COORD / (frameBufferResolution.x / 10.0)));
        highp int yIndex = int(floor(Y_COORD / (frameBufferResolution.x / 10.0)));
        highp int index = yIndex * int(X_COUNT) + xIndex;
        if (blurredCoords[index] == 1) {
            highp vec2 p = vec2(1.0 - textureCoordinate.y ,  textureCoordinate.x) * frameBufferResolution.yx;
            gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / S) * S / frameBufferResolution.yx);
        } else {
            gl_FragColor = texture2D(inputImageTexture, vec2(1.0 - textureCoordinate.y , textureCoordinate.x));
        }
    } else {
    //horizontal
        highp int xIndex = int(floor(gl_FragCoord.y / (frameBufferResolution.y / 10.0)));
        highp int yIndex = int(floor((frameBufferResolution.x - gl_FragCoord.x) / (frameBufferResolution.y / 10.0)));
        highp int index = yIndex * int(X_COUNT) + xIndex;
        if (blurredCoords[index] == 1) {
            highp vec2 p = textureCoordinate.xy * frameBufferResolution.xy;
            gl_FragColor = texture2D(inputImageTexture, vec2(floor((p.x + 0.5) / (frameBufferResolution.y / (float(cellsInWidth) * 0.5))) * (frameBufferResolution.y / (float(cellsInWidth) * 0.5)) / frameBufferResolution.x, floor((p.y + 0.5) / (frameBufferResolution.y / (float(cellsInWidth) * 2.0))) * (frameBufferResolution.y / (float(cellsInWidth) * 2.0)) / frameBufferResolution.y ));
        } else {
            gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
        }
    }
}
