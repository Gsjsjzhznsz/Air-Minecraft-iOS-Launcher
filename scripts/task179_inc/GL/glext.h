/* empty glext stub -- except Task205c lesson anchor below */
#ifndef TASK179_INC_GLEXT_STUB_H_
#define TASK179_INC_GLEXT_STUB_H_

/* ============================================================================
 * Task205c 教训锚（CI run 36739697080，conflicting types 编译失败）：
 * 本 stub 头此前完全为空，导致本地 task193 语法门抓不到"函数定义与
 * 真头（mesa GL/glext.h）原型类型冲突"类 bug——Task205 初版把
 * glGetUniformBlockIndex 写成返回 GLint（用 -1 判未找到），本地门全绿、
 * CI 才报 conflicting types（真头声明 GLuint，未找到 = GL_INVALID_INDEX
 * = 0xFFFFFFFFu）。修法双保险：
 *   (1) 这里放上与 mesa/glext.h 逐字一致的原型（含 GL_INVALID_INDEX），
 *       让本地门从此能抓本函数的返回类型漂移；
 *   (2) verify_task205 C4c 做全量文本级 lint：tinygl4angle.c 的全部
 *       文件作用域定义 vs mesa glext.h 全部 GLAPI 原型比对返回类型。
 * 升级本 stub 时从 Natives/external/mesa/GL/glext.h 复制对应原型，
 * 保留 GLAPI/APIENTRY 宏形态。
 * ==========================================================================*/
#ifndef GLAPI
#define GLAPI extern
#endif
#ifndef APIENTRY
#define APIENTRY
#endif

/* 与 mesa GL/glext.h:1355 逐字一致 */
#define GL_INVALID_INDEX                  0xFFFFFFFFu

/* 与 mesa GL/glext.h:1377 逐字一致（GLchar 由 gl.h 提供） */
GLAPI GLuint APIENTRY glGetUniformBlockIndex (GLuint program, const GLchar *uniformBlockName);

#endif /* TASK179_INC_GLEXT_STUB_H_ */
