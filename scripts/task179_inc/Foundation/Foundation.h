/* Fake Foundation for plain-C harness compile of tinygl4angle.c */
#ifndef FAKE_FOUNDATION_H
#define FAKE_FOUNDATION_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int BOOL;
typedef struct { void *_; } id;
typedef struct { void *_; } NSArray;
typedef struct { void *_; } NSMutableArray;
typedef struct { void *_; } NSString;
typedef struct { void *_; } NSSet;
typedef unsigned long NSUInteger;
#define YES 1
#define NO 0
#define nil NULL
#define NSLog(...) do { } while (0)
#endif
