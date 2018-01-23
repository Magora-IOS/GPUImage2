#extension GL_OES_EGL_image_external : require
precision mediump float;
#define X_COUNT 10
#define Y_COUNT 20
#define S (u_Resolution.x / 20.0) // The cell size.
#define FORCE_FACTOR 1.0
uniform samplerExternalOES u_CamTexture;
uniform vec2 u_Resolution;
uniform int u_BlurredCoords[200];
uniform int u_InStreaming;
uniform float u_RectSize;
varying vec2 v_CamTexCoordinate;
bool shouldAdjustBrightnessOnly() {
    return u_InStreaming == 1;
}
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
    int xIndex  = int(floor(currentFrag.x / u_RectSize));
    int yIndex = int(floor((u_Resolution.y - currentFrag.y) / u_RectSize));
    int index = yIndex * int(X_COUNT) + xIndex; //There's no 'int min(int, int)' function
    return u_BlurredCoords[index] == 1;
}
void main ()
{
    if(shouldBlur(gl_FragCoord.xy)){
        if(shouldAdjustBrightnessOnly()){
            gl_FragColor = texture2D(u_CamTexture, v_CamTexCoordinate);
            //            gl_FragColor = mix(gl_FragColor, Sepia(gl_FragColor), clamp(FORCE_FACTOR, 0.0, 1.0)) * vec4(0.5, 0.5, 0.5, 1.0);
            gl_FragColor = mix(gl_FragColor, vec4(vec3(Luminance(gl_FragColor)), 1.0), clamp(FORCE_FACTOR,0.0,1.0)) * vec4(0.5, 0.5, 0.5, 1.0);
        }else{
            vec2 p = v_CamTexCoordinate.xy * u_Resolution.yx;
            gl_FragColor = texture2D(u_CamTexture, floor((p + 0.5) / S) * S / u_Resolution.yx);
        }
    }else{
        gl_FragColor = texture2D(u_CamTexture, v_CamTexCoordinate);
    }
}
