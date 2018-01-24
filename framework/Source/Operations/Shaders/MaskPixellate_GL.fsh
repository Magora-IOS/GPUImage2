#extension GL_OES_EGL_image_external : require
precision mediump float;
#define X_COUNT 10
#define Y_COUNT 20
#define S (u_Resolution.x / 20.0) // The cell size.
#define FORCE_FACTOR 1.0
uniform sampler2D inputImageTexture;
uniform vec2 u_Resolution;
uniform int blurredCoords[200];

uniform float fractionalWidthOfPixel;
varying vec2 textureCoordinate;
uniform float aspectRatio;

float Luminance(in vec4 color)
{
    //    return (color.r + color.g + color.b ) / 3.0;
    return (color.r * 0.2125 + color.g *0.7154 + color.b * 0.0721);
}
/*
 vec4 Sepia(in vec4 color)
 {
 return vec4(
 clamp(color.r * 0.393 + color.g * 0.769 + color.b * 0.189, 0.0, 1.0),
 clamp(color.r * 0.349 + color.g * 0.686 + color.b * 0.168, 0.0, 1.0),
 clamp(color.r * 0.272 + color.g * 0.534 + color.b * 0.131, 0.0, 1.0),
 color.a
 );
 }
 */
bool shouldBlur(in vec2 currentFrag)
{
    int xIndex  = int(floor(currentFrag.x / fractionalWidthOfPixel));
    int yIndex = int(floor((u_Resolution.y - currentFrag.y) / fractionalWidthOfPixel));
    int index = yIndex * int(X_COUNT) + xIndex; //There's no 'int min(int, int)' function
    return blurredCoords[index] == 1;
}
void main ()
{
    if(shouldBlur(gl_FragCoord.xy)){
            vec2 p = textureCoordinate.xy * u_Resolution.yx;
            gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / S) * S / u_Resolution.yx);
    }else{
        gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
    }
}
