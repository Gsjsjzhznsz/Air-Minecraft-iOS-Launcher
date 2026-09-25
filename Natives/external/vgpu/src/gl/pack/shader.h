


extern char * shaderconv(int, char **, char **, char *, int *, int *, int);
extern int find(char *, char *, char **, char **, int *);
extern int replace(char *, char *, char **);
extern int replace_common(char *, char *, char **, int);			// The last argument specifies the maximum number of times to replace, and when it is negative, the function has the same effect as replace().





/*
char * shaderconv(int number, char ** A, char ** B, char * string, int * length1, int * length, int count);
int find(char *A, char *B, char **ptrA, char **ptr_M, int *count1);
##		find("#version 320 es", "#version 320 es", &string, NULL, NULL) );
## 		// When you just need to find a string, you can write something like this.
int replace(char *A, char *B, char **ptrA);			// replace() has own search function.
*/



extern int Annotation_Detection(char *, char *, int);			// The last parameter is the detection mode. If 0, it is only detected if the current line has "//", if 1, it is detected if its position is contained in a "/*...*/" block.
extern int Skip_Block(char **, char *);
extern void cut_in(char *, char *, char **);				// The first is the pointer to the position to be inserted, the second is the string to be inserted, and the third is the source string to be manipulated.
extern void cut_in_common(char **, char **, int, char **);

