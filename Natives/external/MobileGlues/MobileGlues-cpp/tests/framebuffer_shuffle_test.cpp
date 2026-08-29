// Drives the REAL gl/framebuffer.cpp against a fake driver that records which
// texture is physically attached at each colour attachment point. The question
// the shuffle has to answer correctly is only ever this one: when the
// application draws through draw-buffer slot j, does the texture it named in
// bufs[j] actually receive the pixels?
#include <cstdio>
#include <vector>
#include <map>
#include "gl/framebuffer.h"
#include "gles/loader.h"
#include "gl/mg.h"
#include "config/settings.h"

// --- the four externals framebuffer.cpp reaches for --------------------------
struct gles_func_t g_gles_func{};
namespace FSR1_Context { GLuint g_renderFBO = 0; bool g_dirty = false; }
void set_gl_state_current_draw_fbo(GLuint v) { gl_state->current_draw_fbo = v; }
void mg_set_gl_error(GLenum) {}
int __android_log_print(int, const char*, const char*, ...) { return 0; }
extern "C" void write_log(const char*, ...) {}
global_settings_t global_settings{};
gl_state_s g_default_gl_state{};
thread_local gl_state_t gl_state = &g_default_gl_state;

// --- fake driver ----------------------------------------------------------
static std::map<int, GLuint> physical;   // attachment index -> texture name
static std::vector<GLenum>   draw_list;  // what the driver was last told
static GLuint bound_draw_fb = 0;

static void fake_bind_fb(GLenum, GLuint fb) { bound_draw_fb = fb; }
static void fake_fbtex2d(GLenum, GLenum att, GLenum, GLuint tex, GLint) {
    physical[att - GL_COLOR_ATTACHMENT0] = tex;
}
static void fake_fbrb(GLenum, GLenum att, GLenum, GLuint rb) {
    physical[att - GL_COLOR_ATTACHMENT0] = rb;
}
static void fake_fblayer(GLenum, GLenum att, GLuint tex, GLint, GLint) {
    physical[att - GL_COLOR_ATTACHMENT0] = tex;
}
static void fake_fbtex(GLenum, GLenum att, GLuint tex, GLint) {
    physical[att - GL_COLOR_ATTACHMENT0] = tex;
}
static void fake_drawbuffers(GLsizei n, const GLenum* b) { draw_list.assign(b, b + n); }
static void fake_getintegerv(GLenum pname, GLint* v) {
    *v = (pname == GL_MAX_COLOR_ATTACHMENTS || pname == GL_MAX_DRAW_BUFFERS) ? 8 : 0;
}
static void fake_deletefb(GLsizei, const GLuint*) {}
static void fake_readbuffer(GLenum) {}
static GLenum fake_checkfb(GLenum) { return GL_FRAMEBUFFER_COMPLETE; }
static GLenum fake_geterror() { return GL_NO_ERROR; }
static void fake_blit(GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLbitfield,GLenum) {}

static int fails = 0;
static void expect(const char* what, GLuint got, GLuint want) {
    if (got != want) { printf("  FAIL %-50s physical=%u expected=%u\n", what, got, want); ++fails; }
}

int main() {
    GLES.glBindFramebuffer       = fake_bind_fb;
    GLES.glFramebufferTexture2D  = fake_fbtex2d;
    GLES.glFramebufferRenderbuffer = fake_fbrb;
    GLES.glFramebufferTextureLayer = fake_fblayer;
    GLES.glFramebufferTexture    = fake_fbtex;
    GLES.glDrawBuffers           = fake_drawbuffers;
    GLES.glGetIntegerv           = fake_getintegerv;
    GLES.glDeleteFramebuffers    = fake_deletefb;
    GLES.glReadBuffer            = fake_readbuffer;
    GLES.glCheckFramebufferStatus= fake_checkfb;
    GLES.glGetError              = fake_geterror;
    GLES.glBlitFramebuffer       = fake_blit;

    glBindFramebuffer(GL_FRAMEBUFFER, 7);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 100, 0); // colortex0
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, 101, 0); // colortex1
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT2, GL_TEXTURE_2D, 102, 0); // colortex2

    printf("1. identity order leaves everything alone\n");
    { GLenum b[] = {GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1}; glDrawBuffers(2, b); }
    expect("slot0 holds colortex0", physical[0], 100);
    expect("slot1 holds colortex1", physical[1], 101);

    printf("2. swap: slot0 must receive colortex1, slot1 colortex0\n");
    { GLenum b[] = {GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT0}; glDrawBuffers(2, b); }
    expect("slot0 holds colortex1", physical[0], 101);
    expect("slot1 holds colortex0", physical[1], 100);

    printf("3. back to identity -- the regression a75f818 half-fixed\n");
    { GLenum b[] = {GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1}; glDrawBuffers(2, b); }
    expect("slot0 back to colortex0", physical[0], 100);
    expect("slot1 back to colortex1", physical[1], 101);

    printf("4. single non-identity target -- the destination-victim case\n");
    { GLenum b[] = {GL_COLOR_ATTACHMENT1}; glDrawBuffers(1, b); }
    expect("slot0 holds colortex1", physical[0], 101);
    { GLenum b[] = {GL_COLOR_ATTACHMENT0}; glDrawBuffers(1, b); }
    expect("slot0 back to colortex0", physical[0], 100);
    expect("slot1 back to colortex1", physical[1], 101);

    printf("5. shuffle -> different shuffle, without an identity in between\n");
    { GLenum b[] = {GL_COLOR_ATTACHMENT2}; glDrawBuffers(1, b); }
    expect("slot0 holds colortex2", physical[0], 102);
    { GLenum b[] = {GL_COLOR_ATTACHMENT1}; glDrawBuffers(1, b); }
    expect("slot0 holds colortex1", physical[0], 101);
    expect("slot2 back to colortex2", physical[2], 102);

    printf("6. a renderbuffer attachment survives a call that must not move it\n");
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, 900);
    { GLenum b[] = {GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1}; glDrawBuffers(2, b); }
    expect("slot0 still the renderbuffer", physical[0], 900);

    printf("7. a record survives the table growing under it\n");
    // Every scenario above uses one framebuffer, so until here nothing had ever
    // made the table grow. Sixty-four more names take it through several
    // rehashes and then come back to fbo 7, which must still know its home
    // attachments.
    //
    // This does not reproduce a reference held across an insert -- the case the
    // unique_ptr in the table exists for. It passes with or without it, because
    // no path in framebuffer.cpp currently keeps a framebuffer_t& while asking
    // for a different name; the pointer there is precaution, not load-bearing.
    // What this does catch is a record being lost or corrupted by the growth
    // itself, which nothing else covers.
    for (GLuint extra = 100; extra < 164; ++extra) {
        glBindFramebuffer(GL_FRAMEBUFFER, extra);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 7000 + extra, 0);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 7);
    physical.clear();
    { GLenum b[] = {GL_COLOR_ATTACHMENT1}; glDrawBuffers(1, b); }
    expect("slot0 holds colortex1 after 64 inserts", physical[0], 101);
    { GLenum b[] = {GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1}; glDrawBuffers(2, b); }
    // Scenario 6 left a renderbuffer on attachment 0, so that is what home means
    // here -- and getting it back is the whole point: the record still knows.
    expect("slot0 restored to the renderbuffer", physical[0], 900);
    expect("slot1 restored to colortex1", physical[1], 101);

    printf("8. deleting the framebuffer drops its record\n");
    { GLuint fb = 7; glDeleteFramebuffers(1, &fb); }
    glBindFramebuffer(GL_FRAMEBUFFER, 7);          // driver recycles the name
    physical.clear();
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, 555);
    { GLenum b[] = {GL_COLOR_ATTACHMENT0}; glDrawBuffers(1, b); }
    expect("recycled name did not inherit colortex0", physical[0], 555);

    printf("\n%s (%d failures)\n", fails ? "FAILED" : "all checks passed", fails);
    return fails != 0;
}
