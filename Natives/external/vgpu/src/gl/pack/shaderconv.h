


extern char * old_version;
extern char * new_version;


#define SHADOW 0x00
#define TEXTURE 0x02

#define FUNCTION_NAME 0x03
#define VARIABLE_NAME 0x04

#define GL_INT_ 12
#define GL_UINT_ 13
#define GL_IVEC2_ 14
#define GL_UVEC2_ 15
#define GL_IVEC3_ 16
#define GL_UVEC3_ 17
#define GL_IVEC4_ 18
#define GL_UVEC4_ 19

extern int drawbuffer_fix(char **, char **, int);
extern void func_name_conv(char *, char **);
extern void func_build_in(char **, int, int);

extern void num_add_f(char **);
extern void int_to_float(char **, int);
extern void shader_conv_(char **, char **);


extern int len_name(char *);
extern int judge_name(char *);
extern void cut_in_constructor(char *, char **);
extern void fix_marker(char **);
extern void add_marker(char **);
extern void fix_const(char *, char **);
extern void fix_int_build_in_variable(char *, char **, int);
extern void fix_mod(char **);
extern int skip_block(char *, char *, char *, char *, char **, char **);
extern void in_to_attribute(char **);
extern void fix_layout(char **);


extern void replace_with_char(char *, char, int);
extern void GLSLHeader(char **);

extern void replace_func_name(char *, char *, char **, int);
extern void variable_length_array(char **);
extern void fix_array(char **);
extern int find_extension(char **, int *);