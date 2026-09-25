
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "../../glx/hardext.h"
#include "shaderconv.h"
#include "shader.h"

#include "printf_def.h"

char * old_version = "#version 120";
//char * new_version = "#version 450 compatibility";
char * new_version = "#version 320 es";



#define replace_gl_FragData(N)  \
	char * gl_FragData ##N  = strstr(*glshader_converted, "gl_FragData[" #N "]"); \
	if(gl_FragData ##N ){ \
		pot = replace("gl_FragData[" #N "]", "FragData" #N "", glshader_converted); \
		ptr_cut_in = *glshader_converted + cut_in_offset; \
		cut_in(ptr_cut_in, "layout(location = " #N ") out mediump vec4 FragData" #N ";\n", glshader_converted); \
	}



void shader_conv_(char **glshader_source, char **glshader_converted){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	int lenS;
	
	int vsh = 0;
	int pot = 0;			// A variable that stores the value returned by pot = replace().
	
	if(strstr(*glshader_converted, "gl_Position"))
  		vsh = 1;
	else
  		vsh = 0;
  	
  	// ======== some auxiliary things
  	//pot = replace("__VERSION__", "440", glshader_converted);//				Printf("!", __LINE__);
  	//add_marker(glshader_converted);
  	if(strstr(*glshader_converted, "@@@@FIX_MARKER_VGPU@@")){
  		Printf("add marker succeed!");
  	}else{
  		Printf("failed to add marker!");
  	}
  	/*
  	if(vsh){
  		in_to_attribute(glshader_converted);				// in >> attribute
  	}
  	*/
  	GLSLHeader(glshader_converted);
  	fix_const("const ", glshader_converted);
  	//pot = replace("#ext", "//#ext", glshader_converted);				// #extension
  	
  	// >>>>fixed for GLSL3.x
  	//fix_layout(glshader_converted);
  	if(vsh){
  		//pot = replace("gl_VertexID", "float(gl_VertexID)", glshader_converted);
  		/*
  		fix_int_build_in_variable("gl_VertexID", glshader_converted, GL_INT_);
  		fix_int_build_in_variable("gl_InstanceID", glshader_converted, GL_INT_);
  		*/
  	}else{
  		//fix_int_build_in_variable("gl_VertexID", glshader_converted);
  	}
  	fix_mod(glshader_converted);
  	
  	// ======== Handling the first half of an implicit type conversion.
    //num_add_f(glshader_converted);
  	// ======== from int to float
  	int_to_float(glshader_converted, vsh);//				Printf("!", __LINE__);
	// ======== Keyword
	if(vsh){
		
		pot = replace("attribute", "in", glshader_converted);//				Printf("!", __LINE__);
		pot = replace("varying", "out", glshader_converted);
	}else{
		pot = replace("varying", "in", glshader_converted);//				Printf("!", __LINE__);
	}
	
	
	// ======== Built-in function
	pot = replace("texture2D", "texture", glshader_converted);
	//char * isshadow = strstr(*glshader_converted, "shadow");				printf("shadow = %p \n", isshadow);
	//if(isshadow){
	
	pot = replace("textureSize", "textureSize_", glshader_converted);				// Fix functions that contain integer type.
	pot = replace("texelFetch", "texelFetch_", glshader_converted);
	pot = replace("textureGather", "textureGather_", glshader_converted);	//Printf("Calling %d ", __LINE__);
	replace_func_name("Offset", "Offset_", glshader_converted, FUNCTION_NAME);	//Printf("Calling %d ", __LINE__);
	
	replace_func_name("texture", "texture__", glshader_converted, VARIABLE_NAME);	//Printf("Calling %d ", __LINE__);						// Prevent conflict between variable name and function name.
	replace_func_name("sample", "sample__", glshader_converted, VARIABLE_NAME);	//Printf("Calling %d ", __LINE__);						// Prevent conflict between variable name and function name.
	//}
	
	int cut_in_offset;
  	int isextension = find_extension(glshader_converted, &cut_in_offset);	Printf("extension = %d ", isextension);
  	if(isextension==0){
  		char * ptr_offset = strstr(*glshader_converted, new_version);//				Printf(" cut_in_offset = %d ", cut_in_offset);
  		if(ptr_offset){
  			cut_in_offset = ptr_offset + strlen(new_version) + 2 - *glshader_converted;//				Printf(" cut_in_offset = %d ", cut_in_offset);
  		}else{
  			cut_in_offset = 0;
  		}
  	}
  	char * ptr_cut_in = *glshader_converted + cut_in_offset;
  	
	func_build_in(glshader_converted, cut_in_offset, SHADOW);	//Printf("Calling %d ", __LINE__);//				Printf("!", __LINE__);
	//Printf("Calling %d ", __LINE__);
	
	
	// ======== Built-in variable
	
	if(!vsh){
		
		char * gl_FragColor = strstr(*glshader_converted, "gl_FragColor");//				Printf("!", __LINE__);
		if(gl_FragColor){
			pot = replace("gl_FragColor", "FragColor", glshader_converted);//				Printf("!", __LINE__);
			ptr_cut_in = *glshader_converted + cut_in_offset;
			cut_in(ptr_cut_in, "out mediump vec4 FragColor;\n", glshader_converted);//				Printf("!", __LINE__);
		}
		
		// ======== Fix MRT and OptiFine 
		int fix_mrt = 0;//				Printf("!", __LINE__);
		//fix_mrt = drawbuffer_fix(glshader_source, glshader_converted, cut_in_offset);//				Printf("!", __LINE__);		// You can comment out this statement to disable it.
		if(!fix_mrt){
    		char * gl_FragData = strstr(*glshader_converted, "gl_FragData");//				Printf("!", __LINE__);
    		if(gl_FragData){//				Printf("!", __LINE__);
    			replace_gl_FragData(0)
    			replace_gl_FragData(1)
    			replace_gl_FragData(2)
    			replace_gl_FragData(3)
    			replace_gl_FragData(4)
    			replace_gl_FragData(5)
    			replace_gl_FragData(6)
    			replace_gl_FragData(7)
    		}
		}
		
	}
	
	
	
	// ======== Integer type compatibility
	variable_length_array(glshader_converted);
	fix_array(glshader_converted);	//Printf("Calling %d ", __LINE__);
	//pot = replace("[", "[int(", glshader_converted);//				Printf("!", __LINE__);
	//pot = replace("]", ")]", glshader_converted);//				Printf("!", __LINE__);
	
	// ======== some fix
	fix_marker(glshader_converted);	
	
	//				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
	return;
}






static char _texture2DLod[]=
"vec4 _texture2DLod(sampler2D tex, vec2 coord, int level){\n"
" return textureLod(tex, coord, float(level));\n"
"}"
"vec4 _texture2DLod(sampler2D tex, vec2 coord, float level){\n"
" return textureLod(tex, coord, level);\n"
"}"
"vec4 _texture2D(sampler2D tex, vec2 coord){\n"
" return texture(tex, coord);\n"
"}"
"vec4 _texture2D(sampler2D tex, vec2 coord, int LOD){\n"
" return texture(tex, coord, float(LOD));\n"
"}"
;
static char _shadow2D[]=
"precision mediump sampler2DShadow;\n"
"precision highp float;\n"
"precision mediump int;\n"
/*
"precision highp vec2; precision mediump ivec2;\n"
"precision highp vec3; precision mediump ivec3;\n"
"precision highp vec4; precision mediump ivec4;\n"
*/
/*
"vec4 texelFetch_(sampler2D tex, vec2 P, float lod){\n"				// Fix functions that contain integer type.
" return texelFetch(tex, ivec2(int(P.x), int(P.y)), int(lod));\n"
"}"
"vec4 texelFetch_Offset_(sampler2D tex, vec2 P, float lod, vec2 offset){\n"				// texelFetchOffset
" return texelFetch(tex, ivec2(int(P.x), int(P.y))+ivec2(int(offset.x), int(offset.y)), int(lod));\n"
"}"
"vec4 textureLodOffset_(sampler2D tex, vec2 P, float lod, vec2 offset){\n"				// textureLodOffset
" ivec2 Size = textureSize(tex, 0);\n"
" return textureLod(tex, P+offset/vec2(float(Size.x), float(Size.y)), lod);\n"
"}"
"vec4 textureGradOffset_(sampler2D tex, vec2 P, vec2 dPdx, vec2 dPdy, vec2 offset){\n"				// textureGradOffset
" ivec2 Size = textureSize(tex, 0);\n"
" return textureGrad(tex, P+offset/vec2(float(Size.x), float(Size.y)), dPdx, dPdy);\n"
"}"
"vec4 textureOffset_(sampler2D tex, vec2 P, vec2 offset){\n"				// textureOffset
" ivec2 Size = textureSize(tex, 0);\n"
" return texture(tex, P+offset/vec2(float(Size.x), float(Size.y)));\n"
"}"
"vec4 textureOffset_(sampler2D tex, vec2 P, vec2 offset, float bias){\n"
" ivec2 Size = textureSize(tex, 0);\n"
" return texture(tex, P+offset/vec2(float(Size.x), float(Size.y)), bias);\n"
"}"
"vec2 textureSize_(sampler2D tex, float lod){\n"				// textureSize
" ivec2 Size = textureSize(tex, int(lod));\n"
" return vec2(float(Size.x), float(Size.y));\n"
"}"
"vec2 textureSize_(sampler2DShadow tex, float lod){\n"
" ivec2 Size = textureSize(tex, int(lod));\n"
" return vec2(float(Size.x), float(Size.y));\n"
"}"
"vec4 textureGather_(sampler2D tex, vec2 P){\n"				// textureGather
" return textureGather(tex, P);\n"
"}"
"vec4 textureGather_(sampler2D tex, vec2 P, float comp){\n"
" return textureGather(tex, P, int(comp));\n"
"}"
"vec4 textureGather_Offset_(sampler2D tex, vec2 P, vec2 offset){\n"
" ivec2 Size = textureSize(tex, 0);\n"
" return textureGather(tex, P+offset/vec2(float(Size.x), float(Size.y)));\n"
"}"
"vec4 textureGather_Offset_(sampler2D tex, vec2 P, vec2 offset, float comp){\n"
" ivec2 Size = textureSize(tex, 0);\n"
" return textureGather(tex, P+offset/vec2(float(Size.x), float(Size.y)), int(comp));\n"
"}"
"vec3 shadow2DLod(sampler2DShadow shadow, vec3 coord, int level){\n"
" return vec3(textureLod(shadow, coord, float(level)), 0.0, 0.0);\n"
"}"
"vec3 shadow2DLod(sampler2DShadow shadow, vec3 coord, float level){\n"				// shadow2D wrapper
" return vec3(textureLod(shadow, coord, level), 0.0, 0.0);\n"
"}"
"vec3 shadow2D(sampler2DShadow shadow, vec3 coord){\n"
" return vec3(texture(shadow, coord), 0.0, 0.0);\n"
"}\n"
*/

"vec4 texelFetch_(sampler2D tex, vec2 P, float lod){\n"				// Fix functions that contain integer type.
" return texelFetch(tex, ivec2(int(P.x), int(P.y)), int(lod));\n"
"}"
"vec4 texelFetch_Offset_(sampler2D tex, vec2 P, float lod, vec2 offset){\n"				// texelFetchOffset
" return texelFetch(tex, ivec2(int(P.x), int(P.y))+ivec2(int(offset.x), int(offset.y)), int(lod));\n"
"}"
"vec4 textureLodOffset_(sampler2D tex, vec2 P, float lod, vec2 offset){\n"				// textureLodOffset
" ivec2 Size = textureSize(tex, 0);\n"
" return textureLod(tex, P+offset/vec2(float(Size.x), float(Size.y)), lod);\n"
"}"
"vec4 textureGradOffset_(sampler2D tex, vec2 P, vec2 dPdx, vec2 dPdy, vec2 offset){\n"				// textureGradOffset
" ivec2 Size = textureSize(tex, 0);\n"
" return textureGrad(tex, P+offset/vec2(float(Size.x), float(Size.y)), dPdx, dPdy);\n"
"}"
"vec4 textureOffset_(sampler2D tex, vec2 P, vec2 offset){\n"				// textureOffset
" ivec2 Size = textureSize(tex, 0);\n"
" return texture(tex, P+offset/vec2(float(Size.x), float(Size.y)));\n"
"}"
/*"vec4 textureOffset_(sampler2D tex, vec2 P, vec2 offset, float bias){\n"
" ivec2 Size = textureSize(tex, 0);\n"
" return texture(tex, P+offset/vec2(float(Size.x), float(Size.y)), bias);\n"
"}"*/
"vec2 textureSize_(sampler2D tex, float lod){\n"				// textureSize
" ivec2 Size = textureSize(tex, int(lod));\n"
" return vec2(float(Size.x), float(Size.y));\n"
"}"
"vec2 textureSize_(sampler2DShadow tex, float lod){\n"
" ivec2 Size = textureSize(tex, int(lod));\n"
" return vec2(float(Size.x), float(Size.y));\n"
"}"
"vec4 textureGather_(sampler2D tex, vec2 P){\n"				// textureGather
" return textureGather(tex, P);\n"
"}"
/*"vec4 textureGather_(sampler2D tex, vec2 P, float comp){\n"
" return textureGather(tex, P, int(comp));\n"
"}"*/
"vec4 textureGather_Offset_(sampler2D tex, vec2 P, vec2 offset){\n"
" ivec2 Size = textureSize(tex, 0);\n"
" return textureGather(tex, P+offset/vec2(float(Size.x), float(Size.y)));\n"
"}"
/*"vec4 textureGather_Offset_(sampler2D tex, vec2 P, vec2 offset, float comp){\n"
" ivec2 Size = textureSize(tex, 0);\n"
" return textureGather(tex, P+offset/vec2(float(Size.x), float(Size.y)), int(comp));\n"
"}"*/
/*"vec3 shadow2DLod(sampler2DShadow shadow, vec3 coord, int level){\n"
" return vec3(textureLod(shadow, coord, float(level)), 0.0, 0.0);\n"
"}"*/
"vec3 shadow2DLod(sampler2DShadow shadow, vec3 coord, float level){\n"				// shadow2D wrapper
" return vec3(textureLod(shadow, coord, level), 0.0, 0.0);\n"
"}"
"vec3 shadow2D(sampler2DShadow shadow, vec3 coord){\n"
" return vec3(texture(shadow, coord), 0.0, 0.0);\n"
"}\n"
;


void func_build_in(char **converted, int cut_in_offset, int type){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	char * ptr_cut_in = *converted + cut_in_offset;
	switch(type){
		case SHADOW:
			cut_in(ptr_cut_in, _shadow2D, converted);//				Printf("!", __LINE__);
			break;
		case TEXTURE:
			cut_in(ptr_cut_in, _texture2DLod, converted);//				Printf("!", __LINE__);
			break;
	}//				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
	return;
}


void GLSLHeader(char **source){
	int pot;
	if(hardext.glsl320es){		// pack/shaderconv.h shaderconv.c: old_version new_version
  		pot = replace_common(old_version, new_version, source, 1);
  		return;
  	}
  	if(hardext.glsl310es){
  		pot = replace_common(old_version, new_version, source, 1);
  		return;
  	}
  	if(hardext.glsl300es){
  		pot = replace_common(old_version, new_version, source, 1);
  		return;
  	}
  	return;
}


void num_add_f(char **source){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	char * ptr = *source;
	int lenS = strlen(*source);				Printf(" lenS = %d ", lenS);
	int num = 0;
	int max = (int)(lenS*0.4);
	char ** ptr_arr = (char **)malloc((max+1)*sizeof(char*));//				Printf("!", __LINE__);			// Pointer array.
	lenS--;
	int start=0;
	for(int n=0; n<lenS; n++){
		if( ptr[n]=='#' ){
			if( ptr[n+1]=='d' ){				// if #define
				continue;
			}else{
				while( ptr[n]!='\n' && n<lenS ){					// If the preprocessing directive is not #define,
					n++;
				}
				continue;
			}
		}
		if(n==0){continue;}
		if( (ptr[n]>='0' && ptr[n]<='9') || ptr[n]=='.' ){				// If the character is a number,
			if( ptr[n]=='.' ){
				if( !(ptr[n-1]>='0' && ptr[n-1]<='9') ){			// ...).rgb
					start=0;
					continue;				//#define ENTITY_LEAVES        8.0.0
				}
			}
			if( ptr[n+1]=='f' ){				// Check to see if there is an existing f,
				if(start){
    				ptr[n+1]=' ';				// "0f" >> "0 "
    				ptr_arr[num] = ptr+n+1;
    				num++;
    				start=0;
				}
				continue;
			}
			if( (ptr[n-1]>='0' && ptr[n-1]<='9') || ptr[n-1]=='.' ){				// If the character is still preceded by a number,
				continue;
			}						// If the current position is not in a contiguous number queue,
			if( !( (ptr[n-1]>='a' && ptr[n-1]<='z') || (ptr[n-1]>='A' && ptr[n-1]<='Z') || ptr[n-1]=='_' || ptr[n-1]=='[' || ptr[n-1]==']' ) ){				// If the character is not preceded by the name of a variable or function or array.
				start=1;
				continue;
			}else{
				start=0;
				continue;
			}
		}else{				// _gl4es_MultiTexCoord0.fstpq
			if(start){
				ptr_arr[num] = ptr+n;				// if so, the number will be suffixed with f to make it a floating point number.
				num++;
				start=0;				// update the start.
				continue;
			}else{
				continue;
			}
		}
	}				Printf(" num = %d ", num);
	if(num>0){
		char ** f_arr = (char **)malloc(num*sizeof(char*));//				Printf("!", __LINE__);
    	char f_A[] = "0";
    	char f_B[] = ".0";
    	char f_C[] = "";
    	char * ptr_f = NULL;
    	int isfloat = 0;
    	for(int n=0; n<num; n++){
    		isfloat = 0;
    		ptr_f = ptr_arr[n];
    		if( !( (*ptr_f>='a' && *ptr_f<='z') || (*ptr_f>='A' && *ptr_f<='Z') || *ptr_f=='_' ) ){
				while( !( (*ptr_f>='0' && *ptr_f<='9') || *ptr_f=='.' ) ){				// Corrected Offset.
					ptr_f--;
				}
				for(int m=0; *(ptr_f-m)!='\n'; m++){
					if( *(ptr_f-m)>='0' && *(ptr_f-m)<='9' ){
						continue;
					}
					if( *(ptr_f-m)=='.' ){
						isfloat=1;
						break;				//#define ENTITY_LEAVES        8.0.0
					}
					break;
				}
				if(isfloat){				// If the number has a decimal point,
					f_arr[n]=f_A;
				}else{
					f_arr[n]=f_B;
				}
    		}else{
    			f_arr[n]=f_C;
    		}
    	}
    	cut_in_common(ptr_arr, f_arr, num, source);//				Printf("!", __LINE__);
    	free(f_arr);//				Printf(" free = %p ", f_arr);
    }
	free(ptr_arr);//				Printf(" free = %p ", ptr_arr);
	//				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
	return;
}



void int_to_float(char **source, int vsh){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	// >>>> replace "int" to "float"
	int pot;
	int len_highp = strlen("highp");
	int len_mediump = strlen("mediump");
	int len_lowp = strlen("lowp");
	int len_uniform = strlen("uniform");
	int len_attribute = strlen("attribute");
	int lenS = strlen(*source);
	
	
	// >>>> uniform
	cut_in_constructor("uniform", source);				// int/ivec2/3/4 >> float/vec2/3/4
					Printf(" vsh = %d", vsh);
	// >>>> attribute
	if(vsh){
		cut_in_constructor("attribute", source);				// int/ivec2/3/4 >> ivec4 >> float/vec2/3/4
	}
	
	
	// uint
	int len_uint = strlen("uint");
	int len_s_to_m = 0;
	int num_uint = 0;
	int num_uint_ = 0;
	char **ptr_uint = (char **)malloc( ((uint)(lenS/len_uint)+1)*sizeof(char*) );
	//char **ptr_uint_ = (char **)malloc( ((uint)(lenS/len_uint)+1)*sizeof(char*) );
	pot = find("uint", "uint", source, ptr_uint, &num_uint);
	char *ptrm = NULL;
	for(int n=0; n<num_uint; n++){
		ptrm = ptr_uint[n];
		if(ptrm!=*source){
			if(judge_name(ptrm-1)){
				memmove(ptr_uint[n], "####", 4);
				ptr_uint[n]=NULL;
				continue;
			}
		}
		*ptrm = '\0';
		len_s_to_m = ptrm - *source;
		for(int m=0; m<len_s_to_m; m++){
			if(m==0){continue;}
			if(*(ptrm-m)=='\n'){break;}
			if(*(ptrm-m)==' '){						// Check backwards from "uint" position to see if the string has "uniform" and "attribute", and make sure the path is full of spaces ' '.
				continue;
			}else{
				if(*(ptrm-m-1)=='r' && *(ptrm-m)=='m'){				// First, fuzzy judgment is carried out to reduce the consumption caused by the string comparison function.
					if(*(ptrm-m-len_uniform)=='\n' || *(ptrm-m-len_uniform)==';' || *(ptrm-m-len_uniform)==' '){
    					if(strncmp(ptrm-m-len_uniform+1, "uniform", len_uniform)==0){
    						memmove(ptr_uint[n], "####", 4);
    						//ptr_uint_[num_uint_]=ptr_uint[n];
    						num_uint_++;
    						break;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='t' && *(ptrm-m)=='e'){
					if(*(ptrm-m-len_attribute)=='\n' || *(ptrm-m-len_attribute)==';' || *(ptrm-m-len_attribute)==' '){
    					if(strncmp(ptrm-m-len_attribute+1, "attribute", len_attribute)==0){
    						memmove(ptr_uint[n], "$$$$", 4);
    						//ptr_uint_[num_uint_]=ptr_uint[n];
    						num_uint_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='m' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_mediump)==' '){
    					if(strncmp(ptrm-m-len_mediump+1, "mediump", len_mediump)==0){
    						memmove(ptr_uint[n], "####", 4);
    						//ptr_uint_[num_uint_]=ptr_uint[n];
    						num_uint_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='h' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_highp)==' '){
    					if(strncmp(ptrm-m-len_highp+1, "highp", len_highp)==0){
    						memmove(ptr_uint[n], "####", 4);
    						//ptr_uint_[num_uint_]=ptr_uint[n];
    						num_uint_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='w' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_lowp)==' '){
    					if(strncmp(ptrm-m-len_lowp+1, "lowp", len_lowp)==0){
    						memmove(ptr_uint[n], "####", 4);
    						//ptr_uint_[num_uint_]=ptr_uint[n];
    						num_uint_++;
    						break;
    					}
    				}
				}
			}
		}
		if(*(ptr_uint[n])!='#' && *(ptr_uint[n])!='$'){
			*(ptr_uint[n]) = 'u';
		}
	}
	// uvecn
	int len_uvec = strlen("uvec");
	len_s_to_m = 0;
	int num_uvec = 0;
	int num_uvec_ = 0;
	char **ptr_uvec = (char **)malloc( ((int)(lenS/len_uvec)+1)*sizeof(char*) );
	//char **ptr_uvec_ = (char **)malloc( ((int)(lenS/len_uvec)+1)*sizeof(char*) );
	pot = find("uvec", "uvec", source, ptr_uvec, &num_uvec);
	ptrm = NULL;
	for(int n=0; n<num_uvec; n++){
		ptrm = ptr_uvec[n];
		if(ptrm!=*source){
			if(judge_name(ptrm-1)){
				memmove(ptr_uvec[n], ">>>>", 4);
				ptr_uvec[n]=NULL;
				continue;
			}
		}
		if( !(*(ptrm+4)>='2' && *(ptrm+4)<='4') ){				// Check if it is vec2/3/4.
			memmove(ptr_uvec[n], ">>>>", 4);
			ptr_uvec[n]=NULL;
			continue;
		}
		*ptrm = '\0';
		len_s_to_m = ptrm - *source;
		for(int m=0; m<len_s_to_m; m++){
			if(m==0){continue;}
			if(*(ptrm-m)=='\n'){break;}
			if(*(ptrm-m)==' '){						// Check backwards from "uvec" position to see if the string has "uniform" and "attribute", and make sure the path is full of spaces ' '.
				continue;
			}else{
				if(*(ptrm-m-1)=='r' && *(ptrm-m)=='m'){				// First, fuzzy judgment is carried out to reduce the consumption caused by the string comparison function.
					if(*(ptrm-m-len_uniform)=='\n' || *(ptrm-m-len_uniform)==';' || *(ptrm-m-len_uniform)==' '){
    					if(strncmp(ptrm-m-len_uniform+1, "uniform", len_uniform)==0){
    						memmove(ptr_uvec[n], ">>>>", 4);
    						//ptr_uvec_[num_uvec_]=ptr_uvec[n];
    						num_uvec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='t' && *(ptrm-m)=='e'){
					if(*(ptrm-m-len_attribute)=='\n' || *(ptrm-m-len_attribute)==';' || *(ptrm-m-len_attribute)==' '){
    					if(strncmp(ptrm-m-len_attribute+1, "attribute", len_attribute)==0){
    						memmove(ptr_uvec[n], "$$$$$", 5);
    						//ptr_uvec_[num_uvec_]=ptr_uvec[n];
    						num_uvec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='m' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_mediump)==' '){
    					if(strncmp(ptrm-m-len_mediump+1, "mediump", len_mediump)==0){
    						memmove(ptr_uvec[n], ">>>>", 4);
    						//ptr_uvec_[num_uvec_]=ptr_uvec[n];
    						num_uvec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='h' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_highp)==' '){
    					if(strncmp(ptrm-m-len_highp+1, "highp", len_highp)==0){
    						memmove(ptr_uvec[n], ">>>>", 4);
    						//ptr_uvec_[num_uvec_]=ptr_uvec[n];
    						num_uvec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='w' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_lowp)==' '){
    					if(strncmp(ptrm-m-len_lowp+1, "lowp", len_lowp)==0){
    						memmove(ptr_uvec[n], ">>>>", 4);
    						//ptr_uvec_[num_uvec_]=ptr_uvec[n];
    						num_uvec_++;
    						break;
    					}
    				}
				}
			}
		}
		if(*(ptr_uvec[n])!='>' && *(ptr_uvec[n])!='$'){
			*(ptr_uvec[n]) = 'u';
		}
	}
					Printf(" num_uint_ = %d ", num_uint_);
					Printf(" num_uvec_ = %d ", num_uvec_);
	
	pot = replace("uint", "float", source);				// Replace (any) "int" with a "float".
	pot = replace("uvec", "vec", source);
	
	pot = replace(">>>>", "uvec", source);					// Replace previously ignored "###"(int) back to "int".
	pot = replace("####", "uint", source);
	
	pot = replace("$$$$$", "uvec4", source);				// GL3.0 support attribute uint/uvec2/3/4, but GLES3.0 only support attribute uvec4.
	pot = replace("$$$$", "uvec4", source);				// GL3.0 support attribute uint/uvec2/3/4, but GLES3.0 only support attribute uvec4.
	
	free(ptr_uint);
	//free(ptr_uint_);
	free(ptr_uvec);
	//free(ptr_uvec_);
	
	// int
	int len_int = strlen("int");
	len_s_to_m = 0;
	int num_int = 0;
	int num_int_ = 0;
	char **ptr_int = (char **)malloc( ((int)(lenS/len_int)+1)*sizeof(char*) );
	//char **ptr_int_ = (char **)malloc( ((int)(lenS/len_int)+1)*sizeof(char*) );
	pot = find("int", "int", source, ptr_int, &num_int);
	ptrm = NULL;
	for(int n=0; n<num_int; n++){
		ptrm = ptr_int[n];
		if(ptrm!=*source){
			if(judge_name(ptrm-1)){
				memmove(ptr_int[n], "###", 3);
				ptr_int[n]=NULL;
				continue;
			}
		}
		*ptrm = '\0';
		len_s_to_m = ptrm - *source;
		for(int m=0; m<len_s_to_m; m++){
			if(m==0){continue;}
			if(*(ptrm-m)=='\n'){break;}
			if(*(ptrm-m)==' '){						// Check backwards from "int" position to see if the string has "uniform" and "attribute", and make sure the path is full of spaces ' '.
				continue;
			}else{
				if(*(ptrm-m-1)=='r' && *(ptrm-m)=='m'){				// First, fuzzy judgment is carried out to reduce the consumption caused by the string comparison function.
					if(*(ptrm-m-len_uniform)=='\n' || *(ptrm-m-len_uniform)==';' || *(ptrm-m-len_uniform)==' '){
    					if(strncmp(ptrm-m-len_uniform+1, "uniform", len_uniform)==0){
    						memmove(ptr_int[n], "###", 3);
    						//ptr_int_[num_int_]=ptr_int[n];
    						num_int_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='t' && *(ptrm-m)=='e'){
					if(*(ptrm-m-len_attribute)=='\n' || *(ptrm-m-len_attribute)==';' || *(ptrm-m-len_attribute)==' '){
    					if(strncmp(ptrm-m-len_attribute+1, "attribute", len_attribute)==0){
    						memmove(ptr_int[n], "$$$", 3);
    						//ptr_int_[num_int_]=ptr_int[n];
    						num_int_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='m' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_mediump)==' '){
    					if(strncmp(ptrm-m-len_mediump+1, "mediump", len_mediump)==0){
    						memmove(ptr_int[n], "###", 3);
    						//ptr_int_[num_int_]=ptr_int[n];
    						num_int_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='h' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_highp)==' '){
    					if(strncmp(ptrm-m-len_highp+1, "highp", len_highp)==0){
    						memmove(ptr_int[n], "###", 3);
    						//ptr_int_[num_int_]=ptr_int[n];
    						num_int_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='w' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_lowp)==' '){
    					if(strncmp(ptrm-m-len_lowp+1, "lowp", len_lowp)==0){
    						memmove(ptr_int[n], "###", 3);
    						//ptr_int_[num_int_]=ptr_int[n];
    						num_int_++;
    						break;
    					}
    				}
				}
			}
		}
		if(*(ptr_int[n])!='#' && *(ptr_int[n])!='$'){
			*(ptr_int[n]) = 'i';
		}
	}
	// ivecn
	int len_ivec = strlen("ivec");
	len_s_to_m = 0;
	int num_ivec = 0;
	int num_ivec_ = 0;
	char **ptr_ivec = (char **)malloc( ((int)(lenS/len_ivec)+1)*sizeof(char*) );
	//char **ptr_ivec_ = (char **)malloc( ((int)(lenS/len_ivec)+1)*sizeof(char*) );
	pot = find("ivec", "ivec", source, ptr_ivec, &num_ivec);
	ptrm = NULL;
	for(int n=0; n<num_ivec; n++){
		ptrm = ptr_ivec[n];
		if(ptrm!=*source){
			if(judge_name(ptrm-1)){
				memmove(ptr_ivec[n], ">>>>", 4);
				ptr_ivec[n]=NULL;
				continue;
			}
		}
		if( !(*(ptrm+4)>='2' && *(ptrm+4)<='4') ){				// Check if it is vec2/3/4.
			memmove(ptr_ivec[n], ">>>>", 4);
			ptr_ivec[n]=NULL;
			continue;
		}
		*ptrm = '\0';
		len_s_to_m = ptrm - *source;
		for(int m=0; m<len_s_to_m; m++){
			if(m==0){continue;}
			if(*(ptrm-m)=='\n'){break;}
			if(*(ptrm-m)==' '){						// Check backwards from "ivec" position to see if the string has "uniform" and "attribute", and make sure the path is full of spaces ' '.
				continue;
			}else{
				if(*(ptrm-m-1)=='r' && *(ptrm-m)=='m'){				// First, fuzzy judgment is carried out to reduce the consumption caused by the string comparison function.
					if(*(ptrm-m-len_uniform)=='\n' || *(ptrm-m-len_uniform)==';' || *(ptrm-m-len_uniform)==' '){
    					if(strncmp(ptrm-m-len_uniform+1, "uniform", len_uniform)==0){
    						memmove(ptr_ivec[n], ">>>>", 4);
    						//ptr_ivec_[num_ivec_]=ptr_ivec[n];
    						num_ivec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='t' && *(ptrm-m)=='e'){
					if(*(ptrm-m-len_attribute)=='\n' || *(ptrm-m-len_attribute)==';' || *(ptrm-m-len_attribute)==' '){
    					if(strncmp(ptrm-m-len_attribute+1, "attribute", len_attribute)==0){
    						memmove(ptr_ivec[n], "$$$$$", 5);
    						//ptr_ivec_[num_ivec_]=ptr_ivec[n];
    						num_ivec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='m' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_mediump)==' '){
    					if(strncmp(ptrm-m-len_mediump+1, "mediump", len_mediump)==0){
    						memmove(ptr_ivec[n], ">>>>", 4);
    						//ptr_ivec_[num_ivec_]=ptr_ivec[n];
    						num_ivec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='h' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_highp)==' '){
    					if(strncmp(ptrm-m-len_highp+1, "highp", len_highp)==0){
    						memmove(ptr_ivec[n], ">>>>", 4);
    						//ptr_ivec_[num_ivec_]=ptr_ivec[n];
    						num_ivec_++;
    						break;
    					}
    				}
				}
				if(*(ptrm-m-1)=='w' && *(ptrm-m)=='p'){
					if(*(ptrm-m-len_lowp)==' '){
    					if(strncmp(ptrm-m-len_lowp+1, "lowp", len_lowp)==0){
    						memmove(ptr_ivec[n], ">>>>", 4);
    						//ptr_ivec_[num_ivec_]=ptr_ivec[n];
    						num_ivec_++;
    						break;
    					}
    				}
				}
			}
		}
		if(*(ptr_ivec[n])!='>' && *(ptr_ivec[n])!='$'){
			*(ptr_ivec[n]) = 'i';
		}
	}
					Printf(" num_int_ = %d ", num_int_);
					Printf(" num_ivec_ = %d ", num_ivec_);
	
	pot = replace("int", "float", source);				// Replace (any) "int" with a "float".
	pot = replace("ivec", "vec", source);
	
	pot = replace(">>>>", "ivec", source);					// Replace previously ignored "###"(int) back to "int".
	pot = replace("###", "int", source);
	
	pot = replace("$$$$$", "ivec4", source);				// GL3.0 support attribute int/ivec2/3/4, but GLES3.0 only support attribute ivec4.
	pot = replace("$$$", "ivec4", source);				// so we need a converter.
	
	free(ptr_int);
	//free(ptr_int_);
	free(ptr_ivec);
	//free(ptr_ivec_);
	
	
	//				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
	return;
}

int judge_name(char *ptr){
	int n = 0;
	if( (ptr[n]>='a' && ptr[n]<='z') || (ptr[n]>='A' && ptr[n]<='Z') || (ptr[n]>='0' && ptr[n]<='9') || ptr[n]=='_' ){
		n++;
	}
	return n;
}

int len_name(char *ptr){
	int n = 0;
	while( (ptr[n]>='a' && ptr[n]<='z') || (ptr[n]>='A' && ptr[n]<='Z') || (ptr[n]>='0' && ptr[n]<='9') || ptr[n]=='_' ){
		n++;
	}
	return n;
}

void cut_in_constructor(char *A, char **source){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	int pot;
	int len_highp = strlen("highp");
	int len_mediump = strlen("mediump");
	int len_lowp = strlen("lowp");
	int lenS = strlen(*source);
	//char * ptr_constructor[256] = {NULL};
	char ** ptr_constructor = (char **)malloc(256*sizeof(char*));
	//char * ptr_cut_in[256] = {NULL};
	char ** ptr_cut_in = (char **)malloc(256*sizeof(char*));
	int num_constructor = 0;
	char ** arr_name = (char **)malloc(256*sizeof(char*));
	char ** arr_name_ = (char **)malloc(256*sizeof(char*));
	int arr_name_len[256];
	// >>>> constructor
	char * constructors_uniform[4] = {				// int/ivec2/3/4 >> float/vec2/3/4
		" float %s { return float(%s); }\n",
		" vec2 %s { return vec2(float(%s.x), float(%s.y)); }\n",
		" vec3 %s { return vec3(float(%s.x), float(%s.y), float(%s.z)); }\n",
		" vec4 %s { return vec4(float(%s.x), float(%s.y), float(%s.z), float(%s.w)); }\n"
	};																// API			shader
	char * constructors_attribute[4] = {				// int/ivec2/3/4 >> ivec4 >> float/vec2/3/4
		" float %s { return float(%s.x); }\n",
		" vec2 %s { return vec2(float(%s.x), float(%s.y)); }\n",
		" vec3 %s { return vec3(float(%s.x), float(%s.y), float(%s.z)); }\n",
		" vec4 %s { return vec4(float(%s.x), float(%s.y), float(%s.z), float(%s.w)); }\n"
	};
	char ** constructors_;
	if(strncmp(A, "uniform", 7)==0){
		constructors_=constructors_uniform;
	}else{
		constructors_=constructors_attribute;
	}
	
	// >>>> uniform
	int len_uniform = strlen(A);
	int num_uniform = (int)(lenS/len_uniform*0.4);
	char ** ptr_uniform = (char **)malloc((num_uniform+1)*sizeof(char*));//				Printf("!", __LINE__);
	pot = find(A, A, source, ptr_uniform, &num_uniform);				Printf(" num_%s = %d ", A, num_uniform);
	char * ptr_u;
	for(int n=0; n<num_uniform; n++){
		ptr_u = ptr_uniform[n];
		ptr_u += len_uniform;
		if(ptr_u[0]==' '){
			if(ptr_u[1]=='h'){
				ptr_u += len_highp+1;
			}
			if(ptr_u[1]=='m'){
				ptr_u += len_mediump+1;
			}
			if(ptr_u[1]=='l'){
				ptr_u += len_lowp+1;
			}
			if(ptr_u[1]=='i'){
				if(ptr_u[2]=='n'){			// int name
					// Collect variable names
					ptr_u += 4;
					char * ptr_name = ptr_u;
					while(*ptr_name==' ' || *ptr_name=='\n'){
						ptr_name++;
					}
					//int ptr_name_offset = ptr_name - *source;				// Because the source location is moved after the replace call, the pointer offset value is calculated in advance.
					int name_len = len_name(ptr_name);
					arr_name_len[num_constructor] = name_len;
					char * name = (char *)malloc(name_len+1);
					memmove(name, ptr_name, name_len);
					name[name_len]='\0';
					char * name_ = (char *)malloc(name_len+12);
					memmove(name_, ptr_name, name_len);
					memmove(name_+name_len, "_vgpu(void)", 11);
					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
					// Inserts a type constructor at the declaration of the variable name
					char * constructor = constructors_[0];				// A type conversion constructor.
					int len_constructor = snprintf(NULL, 0, constructor, name_, name);				Printf(" \n len_constructor = %d ", len_constructor);
					len_constructor++;
					char * constructor_ = (char *)malloc(len_constructor+1);//				Printf(" constructor_ = %p ", constructor_);
					pot = snprintf(constructor_, len_constructor, constructor, name_, name);
					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
					ptr_constructor[num_constructor] = constructor_;//				Printf("!", __LINE__);				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
					//ptr_name = *source + ptr_name_offset;				// Make the position of ptr_name in the new source the same as that of the original source.
					int x = 0;
					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
						x++;//				Printf("!", __LINE__);
					}
					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
					ptr_cut_in[num_constructor] = ptr_name;//				Printf(" ptr_name = %p ", ptr_name);					// Stores the location of the constructor to be inserted.
					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);
					num_constructor++;
					continue;
				}
				if(ptr_u[2]=='v'){//				Printf(" ivec !", __LINE__);
					if(ptr_u[5]=='2'){//				Printf(" ivec2 !", __LINE__);			// ivec2
						// Collect variable names
    					ptr_u += 6;
    					char * ptr_name = ptr_u;
    					while(*ptr_name==' ' || *ptr_name=='\n'){
    						ptr_name++;
    					}
    					//int ptr_name_offset = ptr_name - *source;
    					int name_len = len_name(ptr_name);
    					arr_name_len[num_constructor] = name_len;
    					char * name = (char *)malloc(name_len+1);
    					memmove(name, ptr_name, name_len);
    					name[name_len]='\0';
    					char * name_ = (char *)malloc(name_len+12);
    					memmove(name_, ptr_name, name_len);
    					memmove(name_+name_len, "_vgpu(void)", 11);
    					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
    					// Inserts a type constructor at the declaration of the variable name
    					char * constructor = constructors_[1];				// A type conversion constructor.
    					int len_constructor = snprintf(NULL, 0, constructor, name_, name, name);				Printf(" \n len_constructor = %d ", len_constructor);
    					len_constructor++;
    					char * constructor_ = (char *)malloc(len_constructor+1);
    					pot = snprintf(constructor_, len_constructor, constructor, name_, name, name);
    					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
    					ptr_constructor[num_constructor] = constructor_;				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
    					//ptr_name = *source + ptr_name_offset;
    					int x = 0;
    					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
    						x++;
    					}
    					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
    					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
    					ptr_cut_in[num_constructor] = ptr_name;					// Stores the location of the constructor to be inserted.
    					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
    					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);
    					num_constructor++;
    					continue;
    				}
					if(ptr_u[5]=='3'){			// ivec3
						// Collect variable names
    					ptr_u += 6;
    					char * ptr_name = ptr_u;
    					while(*ptr_name==' ' || *ptr_name=='\n'){
    						ptr_name++;
    					}
    					//int ptr_name_offset = ptr_name - *source;
    					int name_len = len_name(ptr_name);
    					arr_name_len[num_constructor] = name_len;
    					char * name = (char *)malloc(name_len+1);
    					memmove(name, ptr_name, name_len);
    					name[name_len]='\0';
    					char * name_ = (char *)malloc(name_len+12);
    					memmove(name_, ptr_name, name_len);
    					memmove(name_+name_len, "_vgpu(void)", 11);
    					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
    					// Inserts a type constructor at the declaration of the variable name
    					char * constructor = constructors_[2];				// A type conversion constructor.
    					int len_constructor = snprintf(NULL, 0, constructor, name_, name, name, name);				Printf(" \n len_constructor = %d ", len_constructor);
    					len_constructor++;
    					char * constructor_ = (char *)malloc(len_constructor+1);
    					pot = snprintf(constructor_, len_constructor, constructor, name_, name, name, name);
    					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
    					ptr_constructor[num_constructor] = constructor_;				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
    					//ptr_name = *source + ptr_name_offset;
    					int x = 0;
    					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
    						x++;
    					}
    					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
    					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
    					ptr_cut_in[num_constructor] = ptr_name;					// Stores the location of the constructor to be inserted.
    					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
    					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);
						num_constructor++;
						continue;
					}
					if(ptr_u[5]=='4'){			// ivec4
						// Collect variable names
    					ptr_u += 6;
    					char * ptr_name = ptr_u;
    					while(*ptr_name==' ' || *ptr_name=='\n'){
    						ptr_name++;
    					}
    					//int ptr_name_offset = ptr_name - *source;
    					int name_len = len_name(ptr_name);
    					arr_name_len[num_constructor] = name_len;
    					char * name = (char *)malloc(name_len+1);
    					memmove(name, ptr_name, name_len);
    					name[name_len]='\0';
    					char * name_ = (char *)malloc(name_len+12);
    					memmove(name_, ptr_name, name_len);
    					memmove(name_+name_len, "_vgpu(void)", 11);
    					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
    					// Inserts a type constructor at the declaration of the variable name
    					char * constructor = constructors_[3];				// A type conversion constructor.
    					int len_constructor = snprintf(NULL, 0, constructor, name_, name, name, name, name);				Printf(" \n len_constructor = %d ", len_constructor);
    					len_constructor++;
    					char * constructor_ = (char *)malloc(len_constructor+1);
    					pot = snprintf(constructor_, len_constructor, constructor, name_, name, name, name, name);
    					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
    					ptr_constructor[num_constructor] = constructor_;				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
    					//ptr_name = *source + ptr_name_offset;
    					int x = 0;
    					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
    						x++;
    					}
    					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
    					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
    					ptr_cut_in[num_constructor] = ptr_name;					// Stores the location of the constructor to be inserted.
    					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
    					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);						
						num_constructor++;
						continue;
					}
					continue;
    			}
				continue;
			}
			if(ptr_u[1]=='u'){
				if(ptr_u[2]=='i'){
    				if(ptr_u[3]=='n'){			// uint name
    					// Collect variable names
    					ptr_u += 5;
    					char * ptr_name = ptr_u;
    					while(*ptr_name==' ' || *ptr_name=='\n'){
    						ptr_name++;
    					}
    					//int ptr_name_offset = ptr_name - *source;				// Because the source location is moved after the replace call, the pointer offset value is calculated in advance.
    					int name_len = len_name(ptr_name);
    					arr_name_len[num_constructor] = name_len;
    					char * name = (char *)malloc(name_len+1);
    					memmove(name, ptr_name, name_len);
    					name[name_len]='\0';
    					char * name_ = (char *)malloc(name_len+12);
    					memmove(name_, ptr_name, name_len);
    					memmove(name_+name_len, "_vgpu(void)", 11);
    					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
    					// Inserts a type constructor at the declaration of the variable name
    					char * constructor = constructors_[0];				// A type conversion constructor.
    					int len_constructor = snprintf(NULL, 0, constructor, name_, name);				Printf(" \n len_constructor = %d ", len_constructor);
    					len_constructor++;
    					char * constructor_ = (char *)malloc(len_constructor+1);//				Printf(" constructor_ = %p ", constructor_);
    					pot = snprintf(constructor_, len_constructor, constructor, name_, name);
    					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
    					ptr_constructor[num_constructor] = constructor_;//				Printf("!", __LINE__);				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
    					//ptr_name = *source + ptr_name_offset;				// Make the position of ptr_name in the new source the same as that of the original source.
    					int x = 0;
    					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
    						x++;//				Printf("!", __LINE__);
    					}
    					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
    					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
    					ptr_cut_in[num_constructor] = ptr_name;//				Printf(" ptr_name = %p ", ptr_name);					// Stores the location of the constructor to be inserted.
    					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
    					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);
    					num_constructor++;
    					continue;
    				}
    				continue;
    			}
				if(ptr_u[2]=='v'){
					if(ptr_u[5]=='2'){			// uvec2
						// Collect variable names
    					ptr_u += 6;
    					char * ptr_name = ptr_u;
    					while(*ptr_name==' ' || *ptr_name=='\n'){
    						ptr_name++;
    					}
    					//int ptr_name_offset = ptr_name - *source;
    					int name_len = len_name(ptr_name);
    					arr_name_len[num_constructor] = name_len;
    					char * name = (char *)malloc(name_len+1);
    					memmove(name, ptr_name, name_len);
    					name[name_len]='\0';
    					char * name_ = (char *)malloc(name_len+12);
    					memmove(name_, ptr_name, name_len);
    					memmove(name_+name_len, "_vgpu(void)", 11);
    					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
    					// Inserts a type constructor at the declaration of the variable name
    					char * constructor = constructors_[1];				// A type conversion constructor.
    					int len_constructor = snprintf(NULL, 0, constructor, name_, name, name);				Printf(" \n len_constructor = %d ", len_constructor);
    					len_constructor++;
    					char * constructor_ = (char *)malloc(len_constructor+1);
    					pot = snprintf(constructor_, len_constructor, constructor, name_, name, name);
    					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
    					ptr_constructor[num_constructor] = constructor_;				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
    					//ptr_name = *source + ptr_name_offset;
    					int x = 0;
    					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
    						x++;
    					}
    					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
    					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
    					ptr_cut_in[num_constructor] = ptr_name;					// Stores the location of the constructor to be inserted.
    					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
    					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);
    					num_constructor++;
    					continue;
    				}
					if(ptr_u[5]=='3'){			// uvec3
						// Collect variable names
    					ptr_u += 6;
    					char * ptr_name = ptr_u;
    					while(*ptr_name==' ' || *ptr_name=='\n'){
    						ptr_name++;
    					}
    					//int ptr_name_offset = ptr_name - *source;
    					int name_len = len_name(ptr_name);
    					arr_name_len[num_constructor] = name_len;
    					char * name = (char *)malloc(name_len+1);
    					memmove(name, ptr_name, name_len);
    					name[name_len]='\0';
    					char * name_ = (char *)malloc(name_len+12);
    					memmove(name_, ptr_name, name_len);
    					memmove(name_+name_len, "_vgpu(void)", 11);
    					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
    					// Inserts a type constructor at the declaration of the variable name
    					char * constructor = constructors_[2];				// A type conversion constructor.
    					int len_constructor = snprintf(NULL, 0, constructor, name_, name, name, name);				Printf(" \n len_constructor = %d ", len_constructor);
    					len_constructor++;
    					char * constructor_ = (char *)malloc(len_constructor+1);
    					pot = snprintf(constructor_, len_constructor, constructor, name_, name, name, name);
    					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
    					ptr_constructor[num_constructor] = constructor_;				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
    					//ptr_name = *source + ptr_name_offset;
    					int x = 0;
    					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
    						x++;
    					}
    					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
    					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
    					ptr_cut_in[num_constructor] = ptr_name;					// Stores the location of the constructor to be inserted.
    					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
    					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);
						num_constructor++;
						continue;
					}
					if(ptr_u[5]=='4'){			// uvec4
						// Collect variable names
    					ptr_u += 6;
    					char * ptr_name = ptr_u;
    					while(*ptr_name==' ' || *ptr_name=='\n'){
    						ptr_name++;
    					}
    					//int ptr_name_offset = ptr_name - *source;
    					int name_len = len_name(ptr_name);
    					arr_name_len[num_constructor] = name_len;
    					char * name = (char *)malloc(name_len+1);
    					memmove(name, ptr_name, name_len);
    					name[name_len]='\0';
    					char * name_ = (char *)malloc(name_len+12);
    					memmove(name_, ptr_name, name_len);
    					memmove(name_+name_len, "_vgpu(void)", 11);
    					name_[name_len+11]='\0';				Printf(" \n name_ >>>>\n%s\n>>>> \n", name_);
    					// Inserts a type constructor at the declaration of the variable name
    					char * constructor = constructors_[3];				// A type conversion constructor.
    					int len_constructor = snprintf(NULL, 0, constructor, name_, name, name, name, name);				Printf(" \n len_constructor = %d ", len_constructor);
    					len_constructor++;
    					char * constructor_ = (char *)malloc(len_constructor+1);
    					pot = snprintf(constructor_, len_constructor, constructor, name_, name, name, name, name);
    					constructor_[len_constructor]='\0';				Printf(" \n constructor_ >>>>\n%s\n>>>> \n", constructor_);
    					ptr_constructor[num_constructor] = constructor_;				// Here, the constructor pointers are stored in an array of pointers, which are inserted at one time after all the constructors have been created.
    					//ptr_name = *source + ptr_name_offset;
    					int x = 0;
    					while(ptr_name[x] != ';' && ptr_name[x] != '\0'){
    						x++;
    					}
    					if(ptr_name[x] == ';'){ x++; ptr_name += x; }
    					if(ptr_name[x] == '\0'){ ptr_name += name_len; }
    					ptr_cut_in[num_constructor] = ptr_name;					// Stores the location of the constructor to be inserted.
    					arr_name[num_constructor]=name;//				Printf(" free = %p ", name);
    					arr_name_[num_constructor]=name_;//				Printf(" free = %p ", name_);						
						num_constructor++;
						continue;
					}
					continue;
    			}
				continue;
			}
			continue;
		}
		continue;
	}				Printf(" num_constructor = %d", num_constructor);
	if(num_constructor>0){//				Printf(" *source = %p  ptr_cut_in[0] = %p ", *source, ptr_cut_in[0]);
    	cut_in_common(ptr_cut_in, ptr_constructor, num_constructor, source);//				Printf("!", __LINE__);					// Insert all constructors.
    	if(num_constructor>256){
    		num_constructor=256;
    	}
    	int num_name = 0;
    	char * name = NULL;
    	lenS = strlen(*source);
    	for(int n=0; n<num_constructor; n++){
    		if(arr_name_len[n]==0){continue;}
    		char * aux = (char *)malloc(arr_name_len[n]+1);
    		for(int x=0; x<arr_name_len[n]; x++){
				aux[x]='$';
			}
			aux[arr_name_len[n]]='\0';
    		char ** ptr_name = (char **)malloc( ((int)(lenS/arr_name_len[n]*0.4)+1)*sizeof(char*) );
    		pot = find(arr_name[n], arr_name[n], source, ptr_name, &num_name);
    		for(int m=0; m<num_name; m++){				// Check whether the variable name is a separate variable name.
        		name = ptr_name[m];
        		name--;
        		if( (*name>='a' && *name<='z') || (*name>='A' && *name<='Z') || (*name>='0' && *name<='9') || *name=='_' || *name=='$' ){
        			name++;
        			memmove(name, aux, arr_name_len[n]);
        			name--;
        		}
        		name++;
        		name += arr_name_len[n];
        		if( (*name>='a' && *name<='z') || (*name>='A' && *name<='Z') || (*name>='0' && *name<='9') || *name=='_' || *name=='$'){
        			name -= arr_name_len[n];
        			memmove(name, aux, arr_name_len[n]);
        			name += arr_name_len[n];
        		}
        		name -= arr_name_len[n];
        	}
        	int vec_num = 2;									//constructor type
        	if( *(ptr_constructor[n]+1)=='f' ){ vec_num += 0; }	//float
        	if( *(ptr_constructor[n]+4)=='2' ){ vec_num += 1; }	//vec2
        	if( *(ptr_constructor[n]+4)=='3' ){ vec_num += 2; }	//vec3
        	if( *(ptr_constructor[n]+4)=='4' ){ vec_num += 3; }	//vec4
        	pot = replace(arr_name[n], arr_name_[n], source);								//  Replace the variable names to make the constructor work for them.
        	pot = replace_common(arr_name_[n], arr_name[n], source, vec_num);				// Replace the variable name at the declaration and the constructor with original one.
        	pot = replace(aux, arr_name[n], source);
        	lenS += num_name*(strlen(arr_name_[n])-arr_name_len[n]);
        	free(aux);
        }
        for(int m=0; m<num_constructor; m++){
    		free(arr_name[m]);
        	free(arr_name_[m]);
    		free(ptr_constructor[m]);//				Printf(" ptr_constructor[%d] = %p ", m, ptr_constructor[m]);
    	}
    }
    free(ptr_constructor);//				Printf(" free ptr_constructor %p ", ptr_constructor);
    free(ptr_cut_in);//				Printf(" free ptr_cut_in %p ", ptr_cut_in);
	free(ptr_uniform);//				Printf(" free = %p ", ptr_uniform);
	free(arr_name);//				Printf(" free = %p ", arr_name);
	free(arr_name_);//				Printf(" free = %p ", arr_name_);
	//				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
	return;
}




#define replace_N(n, N)  \
				pot = snprintf(c, 5, "%d", n); \
				if((ptr[m])[N]==c[0]){ \
    				pot = snprintf(str, 20, "gl_FragData[%d]", N); \
    				pot = replace(str, "FragData" #n "", converted); \
    				ptr_cut_in = *converted + cut_in_offset; \
    				cut_in(ptr_cut_in, "layout(location = " #n ") out mediump vec4 FragData" #n ";\n", converted); \
    			}

int drawbuffer_fix(char **source, char **converted, int cut_in_offset){
	char * ptr_cut_in;
	int pot=0, count=0, len=0;
	char * ptr[20] = {NULL};
	pot = find("/* DRAWBUFFERS:", "/* DRAWBUFFERS:", source, ptr, &count);				Printf(" /* DRAWBUFFERS: */ = %d ", count);
	for(int n=0; n<count; n++){
		if(Annotation_Detection(ptr[n], *source, 0)){//				Printf("!", __LINE__);
			ptr[n] = NULL;						// If the string has been commented out, it is not processed.
		}
	}
	int ptr_num = 0;
	for(int x=0; x<count; x++){
		if(ptr[x] != NULL){
			ptr_num++;//				Printf("!", __LINE__);
		}
	}
	if(ptr_num){
    	len = strlen("/* DRAWBUFFERS:");//				Printf("!", __LINE__);
    	char str[20] = {' '};
    	char c[5] = {' '};
    	for(int m=0; m<count; m++){
    		if(ptr[m]==NULL){
    			continue;
    		}
    		ptr[m] += len;//				Printf("!", __LINE__);
    		if(*(ptr[m]) == ' '){
    			ptr[m]++;//				Printf("!", __LINE__);
    		}
    		if(*(ptr[m]) == '0' && (*(ptr[m]+1) == ' ' || *(ptr[m]+1) == '.')){				// If it is /* DRAWBUFFERS: 0 */ , this processing is not done.
    			//				Printf("!", __LINE__);
    			return 0;
    		}
    		for(int N=0; ((ptr[m])[N] != ' ' && (ptr[m])[N] != '.') && N<8; N++){
    			/*if((ptr[m])[N]=='0'){
    				pot = snprintf(str, 20, "gl_FragData[%d]", N);
    				pot = replace(str, "FragData0", source);
    				pot = replace_common("0 es", "0 es \nlayout(location = 0) out mediump vec4 FragData0; \n", source, 1);
    			}
    			*///				Printf("!", __LINE__);
    			replace_N(0, N)
    			replace_N(1, N)
    			replace_N(2, N)
    			replace_N(3, N)
    			replace_N(4, N)
    			replace_N(5, N)
    			replace_N(6, N)
    			replace_N(7, N)									// The color buffer specified by the shader is processed by vgpu.
    		}
    	}
    	//pot = replace("/* DRAWBUFFERS:", "/*", converted);//				Printf("!", __LINE__);				// Delete the shader declaration statement.
		return 1;
	}else{
		return 0;
	}
}



void func_name_conv(char *A, char **source){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	int pot = 0;
	int count = 0;
	int lenA = strlen(A);
	int lenS = strlen(*source);
	char ** ptrM = (char **)malloc( ((int)(lenS/lenA*0.3)+1)*sizeof(char *) );
	pot = find(A, A, source, ptrM, &count);
	
	char * conv = (char *)malloc(sizeof(char)*lenA+1);
	conv[lenA] = '\0';
	for(int x=0; x<lenA; x++){
		conv[x] = '#';
	}
	
	char * A_ = (char *)malloc(sizeof(char)*lenA+3);
	A_[lenA+2]='\0';
	A_[lenA+1]='_';
	A_[lenA]='_';				// Add '_' at the end of the variable name to avoid duplicate names, and you can add more.
	memmove(A_, A, lenA);
	
	int lenN;			// The length from ptrm to the end of source.
	char * ptrm;
	int isfunc = 0;
	for(int n=0; n<count; n++){
		ptrm = ptrM[n];
		ptrm += lenA;
		lenN = lenS - (ptrm - *source);
		for(int m=0; m<lenN; m++){
			if(ptrm[m]=='('){
				isfunc = 1;
				break;
    		}
			if(ptrm[m]==',' || ptrm[m]==';' || ptrm[m]=='=' || ptrm[m]=='\n'){
				isfunc = 0;
				break;
			}
			if(ptrm[m]=='+' || ptrm[m]=='-' || ptrm[m]=='*' || ptrm[m]=='/'){
				isfunc = 0;
				break;
			}
    	}
    	if(isfunc==0){
    		memmove(ptrM[n], conv, lenA);				// If it is not a function name, replace it with "####...".
    	}
    }
    pot = replace(conv, A_, source);					// "func_name" >> "func_name_"
    free(ptrM);//				Printf("!", __LINE__);
    free(conv);//				Printf("!", __LINE__);
    free(A_);//				Printf("!", __LINE__);
    //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
    return;
}


void replace_func_name(char *A, char *B, char **source, int mode){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	int pot = 0;
	int count = 0;
	int lenA = strlen(A);
	int lenS = strlen(*source);
	char ** ptrM = (char **)malloc( ((int)(lenS/lenA*0.4)+1)*sizeof(char *) );
	pot = find(A, A, source, ptrM, &count);
	
	//char * conv = B;
	/*char * conv = (char *)malloc(sizeof(char)*lenA+1);
	conv[lenA] = '\0';
	for(int x=0; x<lenA; x++){
		conv[x] = '#';
	}
	*/
	char * A_ = (char *)malloc(sizeof(char)*lenA+1);
	replace_with_char(A_, '$', lenA);
	A_[lenA]='\0';
	
	int lenN;			// The length from ptrm to the end of source.
	char * ptrm;
	int isfunc = 0;
	for(int n=0; n<count; n++){
		ptrm = ptrM[n];
		ptrm += lenA;
		lenN = lenS - (ptrm - *source);
		for(int m=0; m<lenN; m++){
			if(ptrm[m]==' ' || ptrm[m]=='\n'){
				continue;
			}
			/*
			if(ptrm[m]==';' || ptrm[m]==',' || ptrm[m]=='.' ||
			  ptrm[m]=='=' || ptrm[m]=='+' || ptrm[m]=='-' || ptrm[m]=='/' |ptrm[m]=='*'){
				isfunc = VARIABLE_NAME;
				//isfunc = 3;
				break;
    		}*/
			if(ptrm[m]=='('){
				isfunc = FUNCTION_NAME;
				//isfunc = 2;
				break;
    		}else{
				if(judge_name(ptrm+m)==0){
    				isfunc = VARIABLE_NAME;
    				//isfunc = 3;
    				break;
    			}
    		}
    		isfunc = 0;
    		break;
    	}
    	if(isfunc==0){
    		continue;
    	}
    	if(isfunc==FUNCTION_NAME && mode==FUNCTION_NAME){
    	//if(isfunc==2 && mode==FUNCTION_NAME){
    		memmove(ptrM[n], A_, lenA);				// If it is a function name, replace it with "####...".
    		continue;
    	}
    	if(isfunc==VARIABLE_NAME && mode==VARIABLE_NAME){
    	//if(isfunc==3 && mode==VARIABLE_NAME){
    		memmove(ptrM[n], A_, lenA);				// If it is a variable name, replace it with "####...".
    		continue;
    	}
    }
    pot = replace(A_, B, source);					// "func_name" >> "func_name_"
    free(ptrM);//				Printf("!", __LINE__);
    //free(conv);//				Printf("!", __LINE__);
    free(A_);//				Printf("!", __LINE__);
    //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
    return;
}


void variable_length_array(char **source){
	
	
	
	return;
}


void fix_array(char **source){
	int pot;
	int lenS = strlen(*source);
	char * ptr = *source;
	lenS--;
	int left = 0;
	char * ptr_left = NULL;
	for(int n=0; n<lenS; n++){
		if(ptr[n]=='['){
			ptr_left = ptr+n;
			left++;
			continue;
		}
		if(left){
			if(ptr[n]==' ' || ptr[n]=='\n'){
				continue;
			}
    		if(ptr[n]==']'){
    			*ptr_left = '$';
    			ptr[n] = '`';
    			ptr_left = NULL;
    		}
    	}
    	left = 0;
	}
	pot = replace("[", "[int(", source);
	pot = replace("]", ")]", source);
	lenS = strlen(*source);
	ptr = *source;
	for(int n=0; n<lenS; n++){
		if(ptr[n]=='$'){
			ptr[n]='[';
		}
		if(ptr[n]=='`'){
			ptr[n]=']';
		}
	}
	
	return;
}


int find_extension(char **source, int *offset){
	int pot;
	int lenS = strlen(*source);
	int len_extension = strlen("#extension ");
	char ** ptrM = (char **)malloc( ((int)(lenS/len_extension*0.4)+1)*sizeof(char*) );
	int num_extension = 0;
	pot = find("#extension ", "#extension ", source, ptrM, &num_extension);
	
	int return_value = 0;
	if(num_extension){
		int len_enable = strlen("enable");
		int len_require = strlen("require");
		int len_warn = strlen("warn");
		int len_disable = strlen("disable");
		for(int m=0; m<=num_extension; m++){
    		if(m==0){continue;}
    		char * ptr = ptrM[num_extension-m];
    		ptr += len_extension;
    		int n;
    		int arrived = 0;
    		for(n=0; ptr[n]!='\0'; n++){
    			if(arrived==0){
        			if(ptr[n]!=':'){
        				continue;
        			}else{
        				arrived++;
        				continue;
        			}
        		}
    			/*if(ptr[n]==':'){
    				arrived++;
    			}*/
    			if(ptr[n]==' '){
    				continue;
    			}
    			if(strncmp(ptr+n, "enable", len_enable)==0){
    				if(ptr[n+len_enable]=='\0'){
    					return_value = 0;
    				}else{
    					ptr[n+len_enable]='\n';
    					n++;
    					ptr += n+len_enable;
    					*offset = ptr - *source;
    					return_value = num_extension;
    				}
    				break;
    			}
    			if(strncmp(ptr+n, "require", len_require)==0){
    				if(ptr[n+len_require]=='\0'){
    					return_value = 0;
    				}else{
    					ptr[n+len_require]='\n';
    					n++;
    					ptr += n+len_require;
    					*offset = ptr - *source;
    					return_value = num_extension;
    				}
    				break;
    			}
    			if(strncmp(ptr+n, "warn", len_warn)==0){
    				if(ptr[n+len_warn]=='\0'){
    					return_value = 0;
    				}else{
    					ptr[n+len_warn]='\n';
    					n++;
    					ptr += n+len_warn;
    					*offset = ptr - *source;
    					return_value = num_extension;
    				}
    				break;
    			}
    			if(strncmp(ptr+n, "disable", len_disable)==0){
    				if(ptr[n+len_disable]=='\0'){
    					return_value = 0;
    				}else{
    					ptr[n+len_disable]='\n';
    					n++;
    					ptr += n+len_disable;
    					*offset = ptr - *source;
    					return_value = num_extension;
    				}
    				break;
    			}
    			break;
    		}
    		if(return_value){
    			free(ptrM);
    			return return_value;
    		}
		}
	}
	free(ptrM);
	return 0;
}



void replace_with_char(char *ptr, char c, int len){
	for(int n=0; n<len; n++){
		ptr[n]=c;
	}
	return;
}

void fix_const(char *const_, char **source){
	int num_const = 0;
	int len_const = strlen(const_);
	int lenS = strlen(*source);
	int len_block = lenS;
	char * ptrS = *source;
	char * ptrS_end = *source+lenS;
	char * left=ptrS;
	char * right=ptrS_end;
	char * ptr=ptrS;
	int isblock=0, isconst=0;
	for(int n=0; n<lenS; n++){
		if(n==0){
			isblock=skip_block("{", "}", ptrS, ptrS_end, &left, &right);
		}
		if(isblock){
			n=left-ptrS;
			len_block=right-left;
			len_block -= len_const;
			len_block++;
			len_block += n;
			for(n=n; n<len_block; n++){								// replace "const" inside the block with some spaces.
				for(int m=0; m<len_const; m++){
					if(ptr[n+m]==const_[m]){
						isconst++;
						continue;
					}else{
						isconst=0;
						break;
					}
				}
				if(isconst){
					num_const++;
					replace_with_char(ptr+n, ' ', len_const);
				}
			}
			isblock=0;
			if(right!=ptrS_end){
				right++;
				if(right!=ptrS_end){
					isblock=skip_block("{", "}", right, ptrS_end, &left, &right);				// find the next block.
				}
			}
			continue;
		}else{
			break;
		}
	}
					Printf("num_const = %d \n", num_const);
	return;
}

int skip_block(char *left, char *right, char *start, char *end, char **ptr_left, char **ptr_right){
	int len = end - start;
	int n=0, n_left=0, state=0;
	int num_left=0, num_right=0, isleft=0;
	int len_left=strlen(left), len_right=strlen(right);
	for(n=0; n<len; n++){
		if(strncmp(start+n, left, len_left)==0){
			if(isleft==0){
				n_left=n;
			}
			isleft=1;
			num_left++;
		}
		if(strncmp(start+n, right, len_right)==0){
			num_right++;
		}
		if(num_left!=0 || num_right!=0){
        	if((num_left-num_right)==0){				// "...{......}..."
        		*ptr_left=start+n_left;
        		*ptr_right=start+n;
        		state=1;
        		break;
        	}
        	if((num_left-num_right)<0){				// "......}......"
        		*ptr_left=start;
        		*ptr_right=start+n;
        		state=1;
        		break;
        	}
        }
    }
	if(state==0){
    	if((num_left-num_right)>0){				// "......{......"
    		*ptr_left=start+n_left;
    		*ptr_right=end;
    	}
    }
    
	return num_left+num_right;
}

void fix_int_build_in_variable(char *A, char **source, int type){
	int pot;
	int lenA = strlen(A);
	int lenS = strlen(*source);
	char * aux = (char *)malloc(lenA+1);
	for(int x=0; x<lenA; x++){
		aux[x]='$';
	}
	aux[lenA]='\0';
	
	int num_A = 0;
	char ** ptr_arr = (char **)malloc( ((int)(lenS/lenA*0.6)+1)*sizeof(char*) );
	pot = find(A, A, source, ptr_arr, &num_A);
	
	char * ptr = NULL;
	for(int m=0; m<num_A; m++){				// Check whether the variable name is a separate variable name.
		ptr = ptr_arr[m];
		ptr += lenA;
		if( (*ptr>='a' && *ptr<='z') || (*ptr>='A' && *ptr<='Z') || (*ptr>='0' && *ptr<='9') || *ptr=='_' || *ptr=='$'){
			ptr -= lenA;
			memmove(ptr, aux, lenA);
			ptr += lenA;
		}
		ptr -= lenA;
		if(ptr==*source){continue;}
		ptr--;
		if( (*ptr>='a' && *ptr<='z') || (*ptr>='A' && *ptr<='Z') || (*ptr>='0' && *ptr<='9') || *ptr=='_' || *ptr=='$' ){
			ptr++;
			memmove(ptr, aux, lenA);
			ptr--;
		}
		ptr++;
	}
	
	int len_add = 0;
	char constructor[8];
	switch(type){
		case GL_INT_:
		case GL_UINT_:
			len_add=7;
			memmove(constructor, "float", len_add-2);
			constructor[len_add-2]='\0';
			break;
		case GL_IVEC2_:
		case GL_UVEC2_:
			len_add=6;
			memmove(constructor, "vec2", len_add-2);
			constructor[len_add-2]='\0';
			break;
		case GL_IVEC3_:
		case GL_UVEC3_:
			len_add=6;
			memmove(constructor, "vec3", len_add-2);
			constructor[len_add-2]='\0';
			break;
		case GL_IVEC4_:
		case GL_UVEC4_:
			len_add=6;
			memmove(constructor, "vec4", len_add-2);
			constructor[len_add-2]='\0';
			break;
	}
	char * A_ = (char *)malloc(lenA+len_add+1);
	pot = snprintf(A_, lenA+len_add+1, "%s(%s)", constructor, A);
	A_[lenA+len_add]='\0';
	pot = replace(A, A_, source);				// name >> float(name)
	pot = replace(aux, A, source);
	
	free(A_);
	free(aux);
	free(ptr_arr);
	
	return;
}

void fix_mod(char **source){
	return;
}

void in_to_attribute(char **source){
	int pot;
	int lenS = strlen(*source);
	char * ptr = *source;
	int is_space = 1;
	for(int n=0; n<lenS; n++){				// find "in "
		if(ptr[n]=='i'){
			if(ptr[n+1]=='n'){
				if(ptr[n+2]==' '){
					for(int m=0; m<=n; m++){
						if(m==0){continue;}
						if(ptr[n-m]==' ' || ptr[n-m]=='\n'){
							continue;
						}else{
							is_space = 0;						// (const in
							if(ptr[n-m]==',' || ptr[n-m]=='(' || ptr[n-m]=='t'){				// Determines whether "in" is used to modify a function parameter.
								break;								// If so, ignore.
							}else{
								memmove(ptr+n, "$$", 2);		// If not, mark it and it will be replaced with "attribute".
							}
						}
					}
					if(is_space){
						memmove(ptr+n, "$$", 2);
					}
					continue;
				}
				continue;
			}
			continue;
		}
		continue;
	}
	pot = replace("$$", "attribute", source);
	
	return;
}

void fix_layout(char **source){
	int pot;
	int len_layout = strlen("layout");
	int len_location = strlen("location");
	int lenS = strlen(*source);
	int num_layout = 0;
	char ** ptr_layout_arr = (char **)malloc( ((int)(lenS/len_layout*0.3)+1)*sizeof(char*) );
	pot = find("layout", "layout", source, ptr_layout_arr, &num_layout);
	char * ptr;
	for(int n=0; n<num_layout; n++){				// layout(location = 0.0) >> layout(location = 0)
		ptr = ptr_layout_arr[n];
		ptr += len_layout;
		while(*ptr==' ' || *ptr=='\n'){
			ptr++;
		}
		if(*ptr=='(')
			ptr++;
		else
			continue;
		while(*ptr==' ' || *ptr=='\n'){
			ptr++;
		}
		if(*ptr=='l'){
			if(strncmp(ptr, "location", len_location)==0){
				ptr += len_location;
			}else
				continue;
		}else
			continue;
		while(*ptr==' ' || *ptr=='\n'){
			ptr++;
		}
		if(*ptr=='=')
			ptr++;
		else
			continue;
		while(*ptr==' ' || *ptr=='\n'){
			ptr++;
		}
		if(*ptr>='0' && *ptr<='9'){
			ptr++;
			while(*ptr>='0' && *ptr<='9'){
				ptr++;
			}
		}else
			continue;
		if(*ptr=='.'){
			*ptr=' ';
			*(ptr+1)=' ';
		}
		continue;
	}
	free(ptr_layout_arr);
	
	return;
}
		

void add_marker(char **converted){// ##FIX_MARKER_VGPU##
	int lenS = strlen(*converted);
	int len_marker = strlen("////@@@@FIX_MARKER_VGPU@@@@");
	char * converted_ = (char *)malloc(lenS+len_marker+1);
	memmove(converted_, *converted, lenS);
	memmove(converted_+lenS, "////@@@@FIX_MARKER_VGPU@@@@", len_marker);
	converted_[lenS+len_marker]='\0';
	free(*converted);
	*converted=converted_;
	return;
}
void fix_marker(char **converted){
	char * find_marker = strstr(*converted, "@@@@FIX_MARKER_VGPU@@");
	if(find_marker!=NULL){
		*find_marker='\0';
		Printf("find marker succeed!");
	}else{
		Printf("failed to find marker!");
	}
	return;
}
