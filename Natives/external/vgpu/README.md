# VGPU
The project is a bit like GL4ES, where I want to implement a hardware-accelerated GL converter: when an application calls the GL library, it will be mapped to GLES. In other words, VGPU packages the GLES library as a GL library.
# Current Status
GLAPI wrap:
Most of the GL2.x API and a small amount of GL3.x API(mainly texture and Uniform, because some of the special built-in variables of GLSL120 are now provided by GL4ES by combining API(glUniform) with shader string converters, such as gl_Vertex) now call gl4es.

Global Implicit Type Conversion:
Supported:
int/ivecn <-> float/vecn
uint/uvecn <-> float/vecn
Converters:
Convert most variables in the Shader to the same intermediate type (such as float), and use a type constructor for uniform variables. The converter contains some simple context judgments.
Some problems brought about by this:
The arguments and return values of some built-in functions that use type int are constructed as intermediate types, which causes them to fail. But most of these functions have now been fixed.

Universal Syntax Converter:
Shader conversion is based on ESSL3.x.
For GLSL120+(compatibility), all GLSL120 built-in variables and keywords will be converted to ESSL3.x, such as gl_FragData[n].
For GLSL150+(core), the converter now only has some simple conversions (it is not yet separated from the former).

Other converters:
(Based on simple contextual judgments)
Supports assigning nonconst variables to const variables within a block.
not supported declaring array sizes with simple variables initialized to constants yet.
The % mod operator is not yet supported (this causes MC1.17 to fail because shader uses %)


# About vk
Now and in the future I will work mainly on the vgpu_vk branch.
