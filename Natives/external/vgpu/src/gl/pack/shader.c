// Some extra functions

#include <string.h>
#include <stdlib.h>

// shader
//char * shaderconv(int, char **, char **, char *, int *, int *, int);
//int find(char *, char *, char **, char **, int *);
//int replace(char *, char *, char **);

#include "printf_def.h"


#include "shader.h"

int Annotation_Detection(char *ptr, char *start_ptr, int mode){
	int len = ptr - start_ptr;
	for(int n=0; *(ptr-n) != '\n' && n<=len; n++){			// detect "//"
		if(*(ptr-n)=='/' && *(ptr-n-1)=='/'){
			return 1;
		}
	}
	if(mode==1){
		char *ptrm = ptr;
    	for(int m=0; m<=len; m++){				// detect "/*"
    		int lenblock = 0;
    		if(*(ptrm-1)=='*' && *ptrm=='/'){				// If found "*/", try to match "/*".
    			lenblock = Skip_Block(&ptrm, start_ptr);
    			if(lenblock){
    				m += lenblock;
    				continue;
    			}else{				// If a complete comment block cannot be found, 0 is returned.
    				return 0;
    			}
    		}
    		if(*(ptrm-1)=='/' && *ptrm=='*'){
    			return 1;
    		}
    		ptrm--;
    	}
	}
	return 0;
}


int Skip_Block(char **ptr, char *start_ptr){
	int len = *ptr - start_ptr;
	int pot = 0;
	int lenblock = 0;
	char *ptrm = *ptr;
	
	len -= 2;					// Skip "*/" to start loop.
	ptrm -= 2;
	lenblock = 2;
	for(int m=0; m<=len; m++){
		if(*(ptrm-1)=='*' && *ptrm=='/'){
			pot = Skip_Block(&ptrm, start_ptr);
			lenblock += pot;
			m += pot;
		}
		if(*(ptrm+1)=='/' && *(ptrm+2)=='*'){
			*ptr = ptrm;							// update *ptr, current location.
			return lenblock;
		}
		lenblock++;
		ptrm++;
	}
	return 0;
}




void cut_in_common(char **ptr, char **A, int num, char **source){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	int * lenA = (int *)malloc(num*sizeof(int));//				Printf("", __LINE__);
	int lenA_total = 0;
	for(int n=0; n<num; n++){
		lenA[n] = strlen(A[n]);
		lenA_total += lenA[n];
	}
	int lenS = strlen(*source);//				Printf("", __LINE__);
	int lenC = lenA_total+lenS;
	char * converted = (char *)malloc(lenC+1);//				Printf("", __LINE__);
	
	char * ptr_s = *source;//				Printf("", __LINE__);
	char * ptr_c = converted;//				Printf("", __LINE__);
	int offset = *ptr - ptr_s;				Printf(" offset = %d ", offset);					// Inserts the string into the position ptr points to.
	int offset_ptr = 0;//				Printf("", __LINE__);
	
	memmove(ptr_c, ptr_s, offset);//				Printf("", __LINE__);
	ptr_c += offset;//				Printf("", __LINE__);
	for(int m=0; m<num; m++){
    	memmove(ptr_c, A[m], lenA[m]);
    	ptr_c += lenA[m];
    	if(m<num-1){
    		offset_ptr = ptr[m+1] - ptr[m];
    	}else{
    		offset_ptr = lenS - (ptr[m] - ptr_s);
    	}
    	memmove(ptr_c, ptr[m], offset_ptr);
    	ptr_c += offset_ptr;
    }
    //				Printf("", __LINE__);
	converted[lenC] = '\0';//				Printf("", __LINE__);
	free(lenA);//				Printf(" free = %p ", lenA);
	free(*source);//				Printf(" free = %p ", *source);
	*source = converted;
	//				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
	return;
}





void cut_in(char *ptr, char *A, char **source){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
	int lenA = strlen(A);//     Printf("%d \n", __LINE__);
	int lenS = strlen(*source);//     Printf("%d \n", __LINE__);
	int lenC = lenA+lenS;//     Printf("%d \n", __LINE__);
	char * converted = (char *)malloc(lenC+1);//     Printf("%d \n", __LINE__);
	int offset = ptr - *source;     Printf(" offset = %d \n", offset);					// Inserts the string into the position ptr points to.
	memmove(converted, *source, offset);//     Printf("%d \n", __LINE__);
	memmove(converted+offset, A, lenA);//     Printf("%d \n", __LINE__);
	memmove(converted+offset+lenA, ptr, lenS-offset);//     Printf("%d \n", __LINE__);
	converted[lenC] = '\0';//     Printf("%d \n", __LINE__);
	free(*source);//     Printf("%d \n", __LINE__);//				Printf("", __LINE__);
	*source = converted;//     Printf("%d \n", __LINE__);
	//				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
	return;
}



char * shaderconv(int number, char **A, char **B, char *string, int *length1, int *length, int count){
 
 char **ptrA;
 char *ptrA_;
 ptrA = &ptrA_;
 
 int islength1 = 0;
 if(length1 == NULL){
  length1 = (int *)malloc(count*sizeof(int));			// Create a temporary length1.
  islength1 = 1;
 }
 
 if(count == 1){	// In the case of a single shader source.
  
  if(length == NULL){
   *ptrA = (char *)malloc( (strlen(string)+1)*sizeof(char) );
   memmove(*ptrA, string, strlen(string));		// Copy the original shader source code to A memory block.
   (*ptrA)[strlen(string)] = '\0';
  }
  else{
   *ptrA = (char *)malloc( (*length+1)*sizeof(char) );
   memmove(*ptrA, string, *length);
   (*ptrA)[*length] = '\0';
  }
  
  
  for(int x = 0; x < number; x++){		// Replace one item by another.
   
   *length1 = replace(A[x], B[x], ptrA);	// Passes in the pointer to the string to be searched for, to be replaced, and the pointer to the original shader source code, and returns the length of the processed shader source code.
   										// Inside the function, the memory block pointed to by * ptrA is searched and modified.
   										// The result is then written to a new B memory block (created as A), and then free (* ptrA).
   										// Finally, the pointer to the B memory block is assigned to A * ptrA = ptrB.
   										// In this way, the next round of processing can access the results of the previous round.
  }
 }
 if(count > 1 && length != NULL){
  
  char *ptrA1;
  int all_len = 0;
  int all = 0;
  
  for(int i = 0; i < count; i++){		// For a number of different shader source code one by one.
   
   *ptrA = (char *)malloc( (length[i]+1)*sizeof(char) );
   memmove(*ptrA, string, length[i]);
   (*ptrA)[length[i]] = '\0';
   
   all_len += length[i];
   
   for(int x = 0; x < number; x++){		// Search item by item.
    int length1_ = 0;
    int count_ = 0;
    char * ptrM_[ (int)(strlen(*ptrA)/strlen(A[x]))+1 ];
    
    length1_ = find(A[x], B[x], ptrA, ptrM_, &count_);
    
    if(count_ != 0){
     length1[i] = length1_;
     all_len += length1_ - length[i];	// All _ len is updated each time with the difference (the length returned by the search-the original length).
    }
   }
   
   string += length[i];		// Update the source pointer to copy the correct source block to ptrA.
   all += length[i];
  }
  string -= all;
  all = 0;
  
  ptrA1 = (char *)malloc( (all_len+1)*sizeof(char) );		// Create the final output block.
  free(*ptrA);
  
  
  
  for(int i = 0; i < count; i++){		// For a number of different shader source code one by one.
   
   *ptrA = (char *)malloc( (length[i]+1)*sizeof(char) );
   memmove(*ptrA, string, length[i]);
   (*ptrA)[length[i]] = '\0';
   
   for(int x = 0; x < number; x++){		// Replace one item by another.
   
    length1[i] = replace(A[x], B[x], ptrA);
    
    
    
    
   }
   
   string += length[i];		// Update the source pointer to copy the correct source block to ptrA.
   all += length[i];
   
   memmove(ptrA1, *ptrA, length1[i]);	// Copy each processed shader source block to the total block.
   ptrA1 += length1[i];			// Update ptrA1.
  }
  string -= all;
  all = 0;
  
  free(*ptrA);
  ptrA1 -= all_len;
  *ptrA = ptrA1;
  (*ptrA)[all_len] = '\0';
 }
 
 if(islength1 == 1){		// Release the temporarily created length1.
  free(length1);
 }

 return *ptrA;		// Returns a pointer to the completed memory block.

}



int find(char *A, char *B, char **ptrA, char **ptr_M, int *count1){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
  
 int count = 0;
 char *ptr = NULL;
 int lenA, lenB, differ, len_ptrA;
 lenA = strlen(A);
 lenB = strlen(B);
 len_ptrA = strlen(*ptrA);
 differ = lenB - lenA;
 
 char **ptrM;
 int isptrM1 = 0;
 if(ptr_M != NULL){
  ptrM = ptr_M;
 }
 else{
  char ** ptrM1 = (char **)malloc( ((int)(len_ptrA/lenA)+1)*sizeof(char*) );
  ptrM = ptrM1;
  isptrM1 = 1;
 }
 
 char * ptr_A = *ptrA;
 ptr = strstr(ptr_A, A);		// Gets the initial pointer.
 while(ptr != NULL){
  ptrM[count] = ptr;		// Assign the searched pointer to an array of external pointers.
  count++;
  /*for(int x = 0; x < lenA; x++){
   ptr[x] = '`';
  }*/
  ptr_A = ptr+lenA;				// Skip to the position after the searched string to continue the search.
  ptr = strstr(ptr_A, A);
 }
 /*for(int i = 0; i < count; i++){
  memmove(ptrM[i], A, lenA);		// Replace the string back to the original.
 }*/
 if(count1 != NULL){
  *count1 = count;
 }
 
 if(isptrM1 == 1){
  free(ptrM);//				Printf(" free = %p ", ptrM);
 }
 //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
 return len_ptrA + differ * count;		// Returns the modified length.
 
}



int replace(char *A, char *B, char **ptrA){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
 
 int count = 0;
 char ** ptrM = (char **)malloc( ((int)(strlen(*ptrA)/strlen(A))+1)*sizeof(char*) );
 //char * ptrM[ (int)(strlen(*ptrA)/strlen(A))+1 ];
 int lenA, lenB, differ, len_ptrA, len_ptrB;
 lenA = strlen(A);
 lenB = strlen(B);
 differ = lenB - lenA;
 len_ptrA = strlen(*ptrA); 
 len_ptrB = find(A, B, ptrA, ptrM, &count);		// Obtain the length of the output block and the number of searched strings to be modified.
 len_ptrB = len_ptrA + differ * count;
 
 if(count != 0){
  char *ptrB = (char *)malloc(len_ptrB + 1);
  ptrB[len_ptrB] = '\0';
  
  char *pA = *ptrA;
  char *pB = ptrB;			// Create an action pointer.
  int M_A;			// The difference between the pointer to the current ptrM array and the current pA.
  
  for(int x = 0; x < count; x++){
   
   M_A = ptrM[x] - pA;
   if(M_A > 0){
    memmove(pB, pA, M_A);		// Copy the previous block to ptrB.
    pA += M_A;
    pB += M_A;
   }
   memmove(pB, B, lenB);		// Copy B to ptrB.
   pA += lenA;
   pB += lenB;
  
  }
  if( (*ptrA+len_ptrA-1-pA) > 0 ){
   memmove(pB, pA, *ptrA+len_ptrA-pA);		// Copy the end block to ptrB.
  }
  
  free(ptrM);//				Printf("", __LINE__);
  free(*ptrA);//				Printf(" free = %p ", *ptrA);
  *ptrA = ptrB;
  //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
  return len_ptrB;
 
 }
 else{
  free(ptrM);//				Printf("", __LINE__);
  //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
  return len_ptrB;		// Returns the modified length.
 }

}




int replace_common(char *A, char *B, char **ptrA, int number){//				Printf("&&&&\nStart %d \n&&&&", __LINE__);
 
 int count = 0;
 char ** ptrM = (char **)malloc( ((int)(strlen(*ptrA)/strlen(A))+1)*sizeof(char*) );
 //char * ptrM[ (int)(strlen(*ptrA)/strlen(A))+1 ];
 int lenA, lenB, differ, len_ptrA, len_ptrB;
 lenA = strlen(A);
 lenB = strlen(B);
 differ = lenB - lenA;
 len_ptrA = strlen(*ptrA); 
 len_ptrB = find(A, B, ptrA, ptrM, &count);		// Obtain the length of the output block and the number of searched strings to be modified.
 len_ptrB = len_ptrA + differ * count;
 
 if(count != 0){
  char *ptrB = (char *)malloc(len_ptrB + 1);
  ptrB[len_ptrB] = '\0';
  
  char *pA = *ptrA;
  char *pB = ptrB;			// Create an action pointer.
  int M_A;			// The difference between the pointer to the current ptrM array and the current pA.
  
  if(number > -1){
      for(int x = 0; x < count && x < number; x++){
       
       M_A = ptrM[x] - pA;
       if(M_A > 0){
        memmove(pB, pA, M_A);		// Copy the previous block to ptrB.
        pA += M_A;
        pB += M_A;
       }
       memmove(pB, B, lenB);		// Copy B to ptrB.
       pA += lenA;
       pB += lenB;
      
      }
      if( (*ptrA+len_ptrA-1-pA) > 0 ){
       memmove(pB, pA, *ptrA+len_ptrA-pA);		// Copy the end block to ptrB.
      }
      
      free(ptrM);//				Printf("", __LINE__);
      free(*ptrA);//				Printf(" free = %p ", *ptrA);
      *ptrA = ptrB;
      //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
      return len_ptrB;
  }
  else{
  	  for(int x = 0; x < count && x < number; x++){
       
       M_A = ptrM[x] - pA;
       if(M_A > 0){
        memmove(pB, pA, M_A);		// Copy the previous block to ptrB.
        pA += M_A;
        pB += M_A;
       }
       memmove(pB, B, lenB);		// Copy B to ptrB.
       pA += lenA;
       pB += lenB;
      
      }
      if( (*ptrA+len_ptrA-1-pA) > 0 ){
       memmove(pB, pA, *ptrA+len_ptrA-pA);		// Copy the end block to ptrB.
      }
      
      free(ptrM);//				Printf("", __LINE__);
      free(*ptrA);//				Printf(" free = %p ", *ptrA);
      *ptrA = ptrB;
      //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
      return len_ptrB;
  }
 
 }
 else{
  free(ptrM);//				Printf("", __LINE__);
  //				Printf("&&&&\nEnd %d \n&&&&", __LINE__);
  return len_ptrB;		// Returns the modified length.
 }

}