/* Minimal GL type/stub header for the task179 harness. */
#ifndef GL_STUB_H
#define GL_STUB_H
#include <stddef.h>
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef unsigned int GLbitfield;
typedef int GLsizei;
typedef int GLint;
typedef unsigned char GLboolean;
typedef char GLchar;
typedef float GLfloat;
typedef double GLdouble;   /* real double */
typedef void GLvoid;
typedef unsigned char GLubyte;
#define GL_FALSE 0
#define GL_TRUE 1
#define GL_DEPTH_BUFFER_BIT 0x00000100
#define GL_STENCIL_BUFFER_BIT 0x00000400
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_POINTS 0x0000
#define GL_LINES 0x0001
#define GL_LINE_LOOP 0x0002
#define GL_LINE_STRIP 0x0003
#define GL_TRIANGLES 0x0004
#define GL_TRIANGLE_STRIP 0x0005
#define GL_TRIANGLE_FAN 0x0006
#define GL_QUADS 0x0007
#define GL_QUAD_STRIP 0x0008
#define GL_POLYGON 0x0009
#define GL_VERTEX_ARRAY 0x8074
#define GL_NORMAL_ARRAY 0x8075
#define GL_COLOR_ARRAY 0x8076
#define GL_INDEX_ARRAY 0x8077
#define GL_TEXTURE_COORD_ARRAY 0x8078
#define GL_EDGE_FLAG_ARRAY 0x8079
#define GL_BLEND 0x0BE2
#define GL Lighting 0x0B50
#define GL_LIGHTING 0x0B50
#define GL_LIGHT0 0x4000
#define GL_LIGHT1 0x4001
#define GL_LIGHT2 0x4002
#define GL_LIGHT3 0x4003
#define GL_LIGHT4 0x4004
#define GL_LIGHT5 0x4005
#define GL_LIGHT6 0x4006
#define GL_LIGHT7 0x4007
#define GL_FOG 0x0B60
#define GL_ALPHA_TEST 0x0BC0
#define GL_TEXTURE_2D 0x0DE1
#define GL_PROXY_TEXTURE_1D 0x8063
#define GL_PROXY_TEXTURE_2D 0x8064
#define GL_PROXY_TEXTURE_3D 0x8070
#define GL_MODELVIEW 0x1700
#define GL_PROJECTION 0x1701
#define GL_TEXTURE 0x1702
#define GL_COLOR_ARRAY_POINTER 0
/* glColor4f etc used by tinygl4angle */
void glColor4f(float r, float g, float b, float a);
void glClearDepthf(float d);
void glDepthRangef(float n, float f);
float* glGetFloatv_stub(void);
/* glGetString stub handled inside harness translation unit */
#define GL_UNSIGNED_BYTE 0x1401
#define GL_UNSIGNED_INT 0x1405
#define GL_FLOAT 0x1406
#define GL_DOUBLE 0x140A
#define GL_RGBA 0x1908
#define GL_RGB 0x1907
#define GL_BGRA 0x80E1
#define GL_ALPHA 0x1906
#define GL_LUMINANCE 0x1909
#define GL_LUMINANCE_ALPHA 0x190A
#define GL_NEAREST 0x2600
#define GL_LINEAR 0x2601
#define GL_NEAREST_MIPMAP_NEAREST 0x2700
#define GL_LINEAR_MIPMAP_NEAREST 0x2701
#define GL_NEAREST_MIPMAP_LINEAR 0x2702
#define GL_LINEAR_MIPMAP_LINEAR 0x2703
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_REPEAT 0x2901
#define GL_CLAMP 0x2900
#define GL_ARRAY_BUFFER 0x8892
#define GL_ELEMENT_ARRAY_BUFFER 0x8893
#endif
/* additions for harness */
typedef long long GLint64;
typedef unsigned long long GLuint64;
typedef long long GLsizeiptr;
typedef long long GLintptr;
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#define GL_VERSION 0x1F02
#define GL_RENDERER 0x1F01
#define GL_EXTENSIONS 0x1F03
#define GL_MAX_TEXTURE_SIZE 0x0D33
void glGetFloatv(GLenum pname, GLfloat *params);
void glGetBooleanv(GLenum pname, GLboolean *params);
const GLubyte* glGetString_real(GLenum name);
typedef short GLshort;
typedef unsigned short GLushort;
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices);
void glDrawElementsInstanced(GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei primcount);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glColorMask(GLboolean r, GLboolean g, GLboolean b, GLboolean a);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glBlendFuncSeparate(GLenum, GLenum, GLenum, GLenum);
void glBlendEquationSeparate(GLenum, GLenum);
void glFramebufferTexture2D(GLenum, GLenum, GLenum, GLuint, GLint);
void glGetIntegerv(GLenum pname, GLint *params);
#define GL_PROXY_TEXTURE_RECTANGLE_ARB 0x84F7
#define GL_TEXTURE_WIDTH 0x1000
#define GL_TEXTURE_HEIGHT 0x1001
#define GL_TEXTURE_INTERNAL_FORMAT 0x1003
#define GL_UNSIGNED_INT_8_8_8_8_REV 0x8367
#define GL_TEXTURE_LOD_BIAS 0x8501
#define GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT 0x84FF
typedef signed char GLbyte;
void glVertexAttrib4fv(GLuint index, const GLfloat *v);
#define GL_VENDOR 0x1F00
