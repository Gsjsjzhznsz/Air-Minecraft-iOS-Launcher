#include "hardext.h"

#include "../gl/debug.h"
#include "../gl/gl4es.h"
#include "../gl/init.h"
#include "../gl/logs.h"
#include "../gl/loader.h"
#ifndef ANDROID
#include "rpi.h"
#endif
#include "glx_gbm.h"

/*
#include "gl_ctx/get.h"
#include "gl_ctx/rendering_api_interface.h"
struct {
	void * ptr_library;
	rendering_api_interface_t * ptr_interface;
	api_state_t state;
	api_context_t ctx;
	api_context_t ctx_old;
} gles_ctx_interface;

void Create_Set_CTX(void) {
	printf("VGPU: init: Start Create_Set_CTX");
	int flags = RTLD_LOCAL | RTLD_NOW;
	// import GLESinterface
	gles_ctx_interface.ptr_library = dlopen(LIB_GLES_NAME, flags);
	gles_ctx_interface.ptr_interface = dlsym(gles_ctx_interface.ptr_library, "GLES2Interface");
	// create vkctx and glctx
	//gles_ctx_interface.state = gles_ctx_interface.ptr_interface->init_API_cb();
	gles_ctx_interface.ctx = gles_ctx_interface.ptr_interface->create_context_cb();
	// setCurrent: temporary ctx
	gles_ctx_interface.ctx_old = getGlThreadSpecific();
	setGlThreadSpecific(gles_ctx_interface.ctx);
	
	dlclose(gles_ctx_interface.ptr_library);
	printf("VGPU: init: End Create_Set_CTX");
}
void Delete_CTX(void) {
	printf("VGPU: init: Start Delete_CTX");
	//gles_ctx_interface.ptr_interface->terminate_API_cb();
	gles_ctx_interface.ptr_interface->delete_context_cb(gles_ctx_interface.ctx);
	// setCurrent: oldctx
	setGlThreadSpecific(gles_ctx_interface.ctx_old);
	printf("VGPU: init: End Delete_CTX");
}
*/


#ifndef EGL_PLATFORM_GBM_KHR
#define EGL_PLATFORM_GBM_KHR                     0x31D7
#endif

static int tested = 0;

hardext_t hardext = {0};

static int testGLSL(const char* version, int uniformLoc) {
    // check if glsl 120 shaders are supported... by compiling one !
    LOAD_GLES2_(glCreateShader);
    LOAD_GLES2_(glShaderSource);
    LOAD_GLES2_(glCompileShader);
    LOAD_GLES2_(glGetShaderiv);
    LOAD_GLES2_(glDeleteShader);

    GLuint shad = gles_glCreateShader(GL_VERTEX_SHADER);
    const char* shadTest[4] = {
        version,
        "\n"
        "layout(location = 0) in vec4 vecPos;\n",
        uniformLoc?"layout(location = 0) uniform mat4 matMVP;\n":"uniform mat4 matMVP;\n",
        "void main() {\n"
        " gl_Position = matMVP * vecPos;\n"
        "}\n"
    };
    gles_glShaderSource(shad, 4, shadTest, NULL);
    gles_glCompileShader(shad);
    GLint compiled;
    gles_glGetShaderiv(shad, GL_COMPILE_STATUS, &compiled);
    /*
    if(!compiled) {
        LOAD_GLES2_(glGetShaderInfoLog)
        char buff[500];
        gles_glGetShaderInfoLog(shad, 500, NULL, buff);
        printf("LIBGL: \"%s\" failed, message:\n%s\n", version, buff);
    }
    */
    gles_glDeleteShader(shad);

    return compiled;
}

/*
static int testMAXdrawbuffers(const char* number) {
    LOAD_GLES2_(glCreateShader);
    LOAD_GLES2_(glShaderSource);
    LOAD_GLES2_(glCompileShader);
    LOAD_GLES2_(glGetShaderiv);
    LOAD_GLES2_(glDeleteShader);

    GLuint shad = gles_glCreateShader(GL_FRAGMENT_SHADER);
    const char* shadTest[3] = {
        "#version 310 es"
        "\n"
        "void main() {\n"
        " gl_FragData[ ", number, " -1 ] = vec4(1.0, 1.0, 1.0, 1.0);\n"
        "}\n"
    
    };
    gles_glShaderSource(shad, 3, shadTest, NULL);
    gles_glCompileShader(shad);
    GLint compiled;
    gles_glGetShaderiv(shad, GL_COMPILE_STATUS, &compiled);
    
    if(!compiled) {
        LOAD_GLES2_(glGetShaderInfoLog)
        char buff[500];
        gles_glGetShaderInfoLog(shad, 500, NULL, buff);
        SHUT_LOGD("========\nLIBGL: compile failed, message:\n%s\n", buff);
    }
    
    gles_glDeleteShader(shad);

    return compiled;
}
*/


static int testTextureCubeLod() {
    LOAD_GLES2_(glCreateShader);
    LOAD_GLES2_(glShaderSource);
    LOAD_GLES2_(glCompileShader);
    LOAD_GLES2_(glGetShaderiv);
    LOAD_GLES2_(glDeleteShader);

    GLuint shad = gles_glCreateShader(GL_FRAGMENT_SHADER);
    const char* shadTest[3] = {
        "#version 100",
        "\n"
        "#extension GL_EXT_shader_texture_lod : enable\n"
        "uniform samplerCube samCube;\n"
        "varying mediump vec3 coordCube;\n",
        "void main() {\n"
        " gl_FragColor = textureCubeLod(samCube, coordCube, 0.0);\n"
        "}\n"
    };
    gles_glShaderSource(shad, 3, shadTest, NULL);
    gles_glCompileShader(shad);
    GLint compiled;
    gles_glGetShaderiv(shad, GL_COMPILE_STATUS, &compiled);
    gles_glDeleteShader(shad);

    return compiled;
}

#if defined(NOX11) && defined(NOEGL)
__attribute__((visibility("default")))
#endif
void GetHardwareExtensions(int notest)
{
    if(tested) return;
    // put some default values
    hardext.maxtex = 2;
    hardext.maxsize = 2048;
    hardext.maxlights = 8;
    hardext.maxplanes = 6;
    hardext.maxdrawbuffers = 8;

    hardext.esversion = globals4es.es;
    if(notest) 
    {
#ifndef AMIGAOS4
        SHUT_LOGD("Hardware test disabled, nothing activated...\n");
#endif
        if(hardext.esversion==2) {
            hardext.maxteximage = 4;
            hardext.maxvarying = 8;
            hardext.maxtex = 8;
            hardext.maxvattrib = 16;
            hardext.npot = 1;
            hardext.fbo = 1; 
            hardext.blendcolor = 1;
            hardext.blendsub = 1;
            hardext.blendfunc = 1;
            hardext.blendeq = 1;
            hardext.mirrored = 1;
            hardext.pointsprite = 1;
            hardext.pointsize = 1;
            hardext.cubemap = 1;
            hardext.maxdrawbuffers = 8;
#ifdef AMIGAOS4
            hardext.glsl300es = 1;
#endif
        }
        return;
    }
#if defined(BCMHOST) && !defined(ANDROID)
    rpi_init();
#endif

#ifdef NOEGL
    SHUT_LOGD("Hardware test on current Context...\n");
#else
    
    // used EGL & GLES functions					// Create a temporary EGL context.
    LOAD_EGL(eglBindAPI);
    LOAD_EGL(eglInitialize);
    LOAD_EGL(eglGetDisplay);
    LOAD_EGL(eglCreatePbufferSurface);
    LOAD_EGL(eglDestroySurface);
    LOAD_EGL(eglDestroyContext);
    LOAD_EGL(eglMakeCurrent);
    LOAD_EGL(eglChooseConfig);
    LOAD_EGL(eglCreateContext);
    LOAD_EGL(eglQueryString);
    LOAD_EGL(eglTerminate);

    EGLDisplay eglDisplay;
    EGLSurface eglSurface;
    EGLContext eglContext;

    SHUT_LOGD("Using GLES %s backend\n", (hardext.esversion==1)?"2.0":"3.0");

    // Create a PBuffer first...
    EGLint egl_context_attrib_es2[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    EGLint egl_context_attrib[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    //let's create a PBuffer attributes
    EGLint egl_attribs[10];	// should be enough
    int i = 0;
    egl_attribs[i++] = EGL_WIDTH;
    egl_attribs[i++] = 32;
    egl_attribs[i++] = EGL_HEIGHT;
    egl_attribs[i++] = 32;
    egl_attribs[i++] = EGL_NONE;

    EGLint configAttribs[] = {
#ifdef PANDORA
    // on the Pandora, there don't seem to exist a 8888 PBuffer config for GLES2.
        EGL_RED_SIZE, (hardext.esversion==1)?8:5,
        EGL_GREEN_SIZE, (hardext.esversion==1)?8:6,
        EGL_BLUE_SIZE, (hardext.esversion==1)?8:5,
        EGL_ALPHA_SIZE, (hardext.esversion==1)?8:0,
#else
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
#endif
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, (hardext.esversion==1)?EGL_OPENGL_ES_BIT:EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };

    int configsFound;
    static EGLConfig pbufConfigs[1];



#ifndef NO_GBM
    if (globals4es.usegbm) {
        LoadGBMFunctions();
        eglDisplay = OpenGBMDisplay(EGL_DEFAULT_DISPLAY);
    }
    else
#endif
        eglDisplay = egl_eglGetDisplay(EGL_DEFAULT_DISPLAY);

    egl_eglBindAPI(EGL_OPENGL_ES_API);
    if (egl_eglInitialize(eglDisplay, NULL, NULL) != EGL_TRUE) {
        LOGE("Error while gathering supported extension (eglInitialize: %s), default to none\n", PrintEGLError(0));
        egl_eglTerminate(eglDisplay);
        return;
    }

    egl_eglChooseConfig(eglDisplay, configAttribs, pbufConfigs, 1, &configsFound);
#ifndef NO_GBM
    const char* eglExts = egl_eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
    if(eglExts && strstr(eglExts, "EGL_KHR_platform_gbm ")) {
        SHUT_LOGD("GBM Surfaces supported%s\n", globals4es.usegbm?" and used":"");
        hardext.gbm = 1;
    }
#endif
#ifndef PANDORA
    if(!configsFound) {
        // try without alpha channel
        configAttribs[4*2-1] = 0;
        egl_eglChooseConfig(eglDisplay, configAttribs, pbufConfigs, 1, &configsFound);
        if(configsFound) {
            SHUT_LOGD("No alpha channel in PBuffer context, disabling EGL Alpha channel...\n");
            hardext.eglnoalpha = 1;
        }
    }
#endif
    if(!configsFound) {
        SHUT_LOGE("Error while gathering supported extension (eglChooseConfig: %s), default to none\n", PrintEGLError(0));
        egl_eglTerminate(eglDisplay);
        return;
    }
    eglContext = egl_eglCreateContext(eglDisplay, pbufConfigs[0], EGL_NO_CONTEXT, egl_context_attrib_es2);
    if(!eglContext) {
        SHUT_LOGE("Error while gathering supported extension (eglCreateContext: %s), default to none\n", PrintEGLError(0));
        return;
    }
    eglSurface = egl_eglCreatePbufferSurface(eglDisplay, pbufConfigs[0], egl_attribs);
    if(!eglSurface) {
        SHUT_LOGE("Error while gathering supported extension (eglCreatePBufferSurface: %s), default to none\n", PrintEGLError(0));
        egl_eglDestroyContext(eglDisplay, eglContext);
        egl_eglTerminate(eglDisplay);
        return;
    }
    egl_eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext);
    
    
    
#endif

    tested = 1;
    
    
    
    
    /*
    int flags = RTLD_LOCAL | RTLD_NOW;
	
	gles_ctx_interface.ptr_library = dlopen(LIB_GLES_NAME, flags);
	gles_ctx_interface.ptr_interface = dlsym(gles_ctx_interface.ptr_library, "GLES2Interface");
	// create vkctx and glctx
	gles_ctx_interface.state = gles_ctx_interface.ptr_interface->init_API_cb();
	gles_ctx_interface.ctx = gles_ctx_interface.ptr_interface->create_context_cb();
	// setCurrent
	setGlThreadSpecific(gles_ctx_interface.ctx);
	
	dlclose(gles_ctx_interface.ptr_library);
	*/
	//Create_Set_CTX();
    
    
    LOAD_GLES2_(glGetString);
    LOAD_GLES2_(glGetIntegerv);
    LOAD_GLES2_(glGetError);
    // Now get extensions
    const char* Exts = gles_glGetString(GL_EXTENSIONS);
    SHUT_LOGD("\n========\nGL_EXTENSIONS is :\n%s\n========\n", Exts);
    // Parse them!
    #define S(A, B, C) if(strstr(Exts, A)) { hardext.B = 1; SHUT_LOGD("Extension %s detected%s",A, C?" and used\n":"\n"); } 
    if(hardext.esversion>1) hardext.npot = 1;
    if(strstr(Exts, "GL_APPLE_texture_2D_limited_npot ")) hardext.npot = 1;
    if(strstr(Exts, "GL_IMG_texture_npot ")) hardext.npot = 1; // it should enable mipmap (so hardext.npot=2), but mipmap (so level > 0) needs to be POT-sized?!!
    if(strstr(Exts, "GL_ARB_texture_non_power_of_two ") || strstr(Exts, "GL_OES_texture_npot ")) hardext.npot = 3;
    if(hardext.npot>0) {
        SHUT_LOGD("Hardware %s NPOT detected and used\n", hardext.npot==3?"Full":(hardext.npot==2?"Limited+Mipmap":"Limited"));
    }
    S("GL_EXT_blend_minmax ", blendminmax, 1);
    //S("GL_EXT_draw_buffers ", drawbuffers, 1);
    hardext.drawbuffers = 1;

    /*if(hardext.blendcolor==0) {
        // try by just loading the function
        LOAD_GLES_OR_OES(glBlendColor);
        if(gles_glBlendColor != NULL) {
            hardext.blendcolor = 1;
	        SHUT_LOGD("Extension glBlendColor found and used\n");
	    }
    }*/ // I don't think this is correct
    if(hardext.esversion<2) {
        S("GL_OES_framebuffer_object ", fbo, 1);
        S("GL_OES_point_sprite ", pointsprite, 1); 
        S("GL_OES_point_size_array ", pointsize, 0);
        S("GL_OES_texture_cube_map ", cubemap, 1);
        S("GL_EXT_blend_color ", blendcolor, 1);
        S("GL_OES_blend_subtract ", blendsub, 1);
        S("GL_OES_blend_func_separate ", blendfunc, 1);
        S("GL_OES_blend_equation_separate ", blendeq, 1);
        S("GL_OES_texture_mirrored_repeat ", mirrored, 1);  
    } else {
        hardext.fbo = 1; 
        SHUT_LOGD("FBO are in core, and so used\n");
        hardext.pointsprite = 1;
        SHUT_LOGD("PointSprite are in core, and so used\n");
        hardext.pointsize = 1;
        SHUT_LOGD("CubeMap are in core, and so used\n");
        hardext.cubemap = 1;
        SHUT_LOGD("BlendColor is in core, and so used\n");
        hardext.blendcolor = 1;
        SHUT_LOGD("Blend Substract is in core, and so used\n");
        hardext.blendsub = 1;
        SHUT_LOGD("Blend Function and Equation Separation is in core, and so used\n");
        hardext.blendfunc = 1;
        hardext.blendeq = 1;
        SHUT_LOGD("Texture Mirrored Repeat is in core, and so used\n");
        hardext.mirrored = 1;
    }
    S("GL_OES_mapbuffer ", mapbuffer, 0);
    S("GL_OES_element_index_uint ", elementuint, 1);
    S("GL_OES_packed_depth_stencil ", depthstencil, 1);
    S("GL_OES_depth24 ", depth24, 1);
    S("GL_OES_rgb8_rgba8 ", rgba8, 1);
    S("GL_EXT_multi_draw_arrays ", multidraw, 0);
    if(!globals4es.nobgra) {
        S("GL_EXT_texture_format_BGRA8888 ", bgra8888, 1);
    }
    if(!globals4es.nodepthtex) {
        S("GL_OES_depth_texture ", depthtex, 1);
        S("GL_OES_texture_stencil8 ", stenciltex, 1);
    }
    S("GL_OES_draw_texture ", drawtex, 1);
    S("GL_EXT_texture_rg ", rgtex, 1);
    if(globals4es.floattex) {
        S("GL_OES_texture_float ", floattex, 1);
        S("GL_OES_texture_half_float ", halffloattex, 1);
        S("GL_EXT_color_buffer_float ", floatfbo, 1);
        S("GL_EXT_color_buffer_half_float ", halffloatfbo, 1);
    }

    if (hardext.esversion>1) {
        if(!globals4es.nohighp) {
            S("GL_OES_fragment_precision_high ", highp, 1);
            if(!hardext.highp) {
                // check if highp is supported anyway
                LOAD_GLES2_(glGetShaderPrecisionFormat);
                if(gles_glGetShaderPrecisionFormat) {
                    GLint range[2] = {0};
                    GLint precision=0;
                    gles_glGetShaderPrecisionFormat(GL_FRAGMENT_SHADER, GL_HIGH_FLOAT, range, &precision);
                    if(!(range[0]==0 && range[1]==0 && precision==0)) {
                        hardext.highp = 2;  // no need to declare #entension here
                        SHUT_LOGD("high precision float in fragment shader available and used\n");
                    }
                }
            }
        }
        if(!globals4es.noshaderlod) 
            S("GL_EXT_shader_texture_lod", shaderlod, 1);
        if(hardext.shaderlod) {
            // test is textureCubeLod need EXT or not (seems to be a bug in some PVR driver)
            if(testTextureCubeLod()) {
                hardext.cubelod = 1;
                SHUT_LOGD("textureCubeLod in fragment doesn't need trailing EXT\n");
            }
        }
        S("GL_EXT_frag_depth ", fragdepth, 1);
        gles_glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, &hardext.maxvattrib);
        SHUT_LOGD("Max vertex attrib: %d\n", hardext.maxvattrib);
        S("GL_OES_standard_derivatives ", derivatives, 1);
        S("GL_OES_get_program ", prgbinary, 1);
        if(hardext.prgbinary) {
            gles_glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS_OES, &hardext.prgbin_n);
            SHUT_LOGD("Number of supported Program Binary Format: %d\n", hardext.prgbin_n);
        }
    }
    // Now get some max stuffs
    gles_glGetIntegerv(GL_MAX_TEXTURE_SIZE, &hardext.maxsize);
    SHUT_LOGD("Max texture size: %d\n", hardext.maxsize);
    gles_glGetIntegerv((hardext.esversion==1)?GL_MAX_TEXTURE_UNITS:GL_MAX_TEXTURE_IMAGE_UNITS, &hardext.maxtex);
    if (hardext.esversion==1) {
        gles_glGetIntegerv(GL_MAX_LIGHTS, &hardext.maxlights);
        gles_glGetIntegerv(GL_MAX_CLIP_PLANES, &hardext.maxplanes);
        hardext.maxteximage=hardext.maxtex;
    } else {
        // simulated stuff using the FPE
        hardext.maxlights = 8;
        hardext.maxplanes = 6;
        gles_glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, &hardext.maxteximage);
        gles_glGetIntegerv(GL_MAX_VARYING_VECTORS, &hardext.maxvarying);
        SHUT_LOGD("Max Varying Vector: %d\n", hardext.maxvarying);
        if(hardext.maxvattrib<16 && hardext.maxtex>4)
            hardext.maxtex = 4; // with less then 16 vertexattrib, more then 4 textures seems unreasonnable
    }
    int hardmaxtex = hardext.maxtex;
    if(hardext.maxtex>MAX_TEX) hardext.maxtex=MAX_TEX;      // caping, as there are some fixed-sized array...
    if(hardext.maxteximage>MAX_TEX) hardext.maxteximage=MAX_TEX;
    if(hardext.maxlights>MAX_LIGHT) hardext.maxlights=MAX_LIGHT;                // caping lights too
    if(hardext.maxplanes>MAX_CLIP_PLANES) hardext.maxplanes=MAX_CLIP_PLANES;    // caping planes, even 6 should be the max supported anyway
    SHUT_LOGD("Texture Units: %d/%d (hardware: %d), Max lights: %d, Max planes: %d\n", hardext.maxtex, hardext.maxteximage, hardmaxtex, hardext.maxlights, hardext.maxplanes);
    S("GL_EXT_texture_filter_anisotropic ", aniso, 1);
    if(hardext.aniso) {
        gles_glGetIntegerv(GL_MAX_TEXTURE_MAX_ANISOTROPY, &hardext.aniso);
        if(gles_glGetError()!=GL_NO_ERROR)
            hardext.aniso = 0;
        if(hardext.aniso)
            SHUT_LOGD("Max Anisotropic filtering: %d\n", hardext.aniso);
    }
    //if(hardext.drawbuffers) {
    	hardext.drawbuffers = 8;
        gles_glGetIntegerv(GL_MAX_COLOR_ATTACHMENTS_EXT, &hardext.maxcolorattach);
        gles_glGetIntegerv(GL_MAX_DRAW_BUFFERS_ARB, &hardext.maxdrawbuffers);
    //}
    /*
    int max_draw_buffers = 16;
    if(hardext.maxcolorattach<1)
        hardext.maxcolorattach = 1;
    if(hardext.maxcolorattach>max_draw_buffers)
        hardext.maxcolorattach=max_draw_buffers;
    if(hardext.maxdrawbuffers<1)
        hardext.maxdrawbuffers = 1;
    if(hardext.maxdrawbuffers>max_draw_buffers)
        hardext.maxdrawbuffers=max_draw_buffers;
    */
    SHUT_LOGD("Max Color Attachments: %d / Draw buffers: %d\n", hardext.maxcolorattach, hardext.maxdrawbuffers);
    
    //LOAD_GLES2_(glHint);
    
    
    
    // get GLES driver signatures...
    const char* vendor = gles_glGetString(GL_VENDOR);
    const char* renderer = gles_glGetString(GL_RENDERER);
    //SHUT_LOGD("Hardware vendor is %s\n", vendor);
    SHUT_LOGD("Hardware renderer is %s\n", renderer);
    if(strstr(vendor, "ARM"))
        hardext.vendor = VEND_ARM;
    else if(strstr(vendor, "Imagination Technologies"))
        hardext.vendor = VEND_IMGTEC;
    
    printf("VGPU: Begin testGLSL\n");
    if(hardext.esversion>1) {
        if(testGLSL("#version 120", 1))
            hardext.glsl120 = 1;
        if(testGLSL("#version 300 es", 0))
            hardext.glsl300es = 1;
        if(testGLSL("#version 310 es", 1))
            hardext.glsl310es = 1;
        if(testGLSL("#version 320 es", 1))
            hardext.glsl320es = 1;
    }
    if(hardext.glsl120) {
        SHUT_LOGD("GLSL 120 supported and used\n");
    }
    if(hardext.glsl300es) {
        SHUT_LOGD("GLSL 300 es supported%s\n", (hardext.glsl120||hardext.glsl310es)?"":" and used");
    }
    if(hardext.glsl310es) {
        SHUT_LOGD("GLSL 310 es supported%s\n", hardext.glsl120?"":" and used");
    }
    if(hardext.glsl320es) {
        SHUT_LOGD("GLSL 320 es supported%s\n", hardext.glsl120?"":" and used");
    }
    
    printf("VGPU: End testGLSL\n");
    
    /*
    if(testMAXdrawbuffers("8")){
    	SHUT_LOGD("GLSL supported MAXdrawbuffers = 8 \n");
    }
    if(testMAXdrawbuffers("1")){
    	SHUT_LOGD("GLSL supported MAXdrawbuffers = 1 \n");
    }
    */

#ifndef NOEGL
    if(strstr(egl_eglQueryString(eglDisplay, EGL_EXTENSIONS), "EGL_KHR_gl_colorspace")) {
        SHUT_LOGD("sRGB surface supported\n");
        hardext.srgb = 1;
    }
    if(strstr(egl_eglQueryString(eglDisplay, EGL_EXTENSIONS), "EGL_KHR_image_pixmap")) {
        SHUT_LOGD("EGLImage from Pixmap supported\n");
        hardext.khr_pixmap = 1;
    }
    if(strstr(egl_eglQueryString(eglDisplay, EGL_EXTENSIONS), "EGL_KHR_gl_texture_2D_image")) {
        SHUT_LOGD("EGLImage to Texture2D supported\n");
        hardext.khr_texture_2d = 1;
    }
    if(strstr(egl_eglQueryString(eglDisplay, EGL_EXTENSIONS), "EGL_KHR_gl_renderbuffer_image")) {
        SHUT_LOGD("EGLImage to RenderBuffer supported\n");
        hardext.khr_renderbuffer = 1;
    }
	
	
	
    printf("VGPU: Begin cleanup EGL\n");
    // End, cleanup
    int pot;
    egl_eglMakeCurrent(eglDisplay, 0, 0, EGL_NO_CONTEXT);
    pot= egl_eglDestroySurface(eglDisplay, eglSurface);
    pot= egl_eglDestroyContext(eglDisplay, eglContext);
    printf("VGPU: End cleanup EGL\n");
    pot= egl_eglTerminate(eglDisplay);
    printf("VGPU: End2 cleanup EGL\n");
    
    
    //Delete_CTX();
    
#endif
}
