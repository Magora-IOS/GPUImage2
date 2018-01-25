varying highp vec2 textureCoordinate;

uniform sampler2D inputImageTexture;

uniform highp float fractionalWidthOfPixel;
uniform highp float aspectRatio;
uniform highp vec2 u_Resolution;
uniform highp int blurredCoords[200];

#define X_COUNT 10
#define Y_COUNT 20
#define S (u_Resolution.x / 20.0) // The cell size.


//void main()
//{
//
//    highp vec2 sampleDivisor = vec2(fractionalWidthOfPixel, fractionalWidthOfPixel / aspectRatio);
//
//    highp vec2 samplePos = textureCoordinate - mod(textureCoordinate, sampleDivisor) + 0.5 * sampleDivisor;
//    if (textureCoordinate.x < u_Resolution.x) {
//        gl_FragColor = texture2D(inputImageTexture, samplePos);
//    } else {
//        gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
//    }
//}

bool shouldBlur(in vec2 currentFrag)
{
//    highp int xIndex  = int(floor(currentFrag.x / fractionalWidthOfPixel));
//    highp int yIndex = int(floor((u_Resolution.y - currentFrag.y) / fractionalWidthOfPixel));
//    highp int index = yIndex * int(X_COUNT) + xIndex; //There's no 'int min(int, int)' function
//    return blurredCoords[index] == 1;
    return 1 == 1;
}
void main ()
{
    if(shouldBlur(gl_FragCoord.xy)){
        highp vec2 p = textureCoordinate.xy * u_Resolution.yx;
        gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / S) * S / u_Resolution.yx);
    }else{
        gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
    }
}

//#extension GL_OES_EGL_image_external : require
//precision mediump float;
//#define X_COUNT 10
//#define Y_COUNT 20
////#define S (u_Resolution.x / 20.0) // The cell size.
//#define FORCE_FACTOR 1.0
//uniform sampler2D inputImageTexture;
////uniform vec2 u_Resolution;
////uniform int blurredCoords[200];
//
//uniform float fractionalWidthOfPixel;
//varying vec2 textureCoordinate;
//uniform float aspectRatio;
//
//float Luminance(in vec4 color)
//{
//    //    return (color.r + color.g + color.b ) / 3.0;
//    return (color.r * 0.2125 + color.g *0.7154 + color.b * 0.0721);
//}
///*
// vec4 Sepia(in vec4 color)
// {
// return vec4(
// clamp(color.r * 0.393 + color.g * 0.769 + color.b * 0.189, 0.0, 1.0),
// clamp(color.r * 0.349 + color.g * 0.686 + color.b * 0.168, 0.0, 1.0),
// clamp(color.r * 0.272 + color.g * 0.534 + color.b * 0.131, 0.0, 1.0),
// color.a
// );
// }
// */
//bool shouldBlur(in vec2 currentFrag)
//{
//    int xIndex  = int(floor(currentFrag.x / fractionalWidthOfPixel));
//    int yIndex = int(floor((u_Resolution.y - currentFrag.y) / fractionalWidthOfPixel));
//    int index = yIndex * int(X_COUNT) + xIndex; //There's no 'int min(int, int)' function
//    return 1; // blurredCoords[index] == 1;
//}
//void main ()
//{
//    if(shouldBlur(gl_FragCoord.xy)){
//        vec2 p = textureCoordinate.xy * u_Resolution.yx;
//     //   gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / S) * S / u_Resolution.yx);
//        gl_FragColor = texture2D(inputImageTexture, floor((p + 0.5) / 10) * 10 / 100);
//    }else{
//        gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
//    }
//}

