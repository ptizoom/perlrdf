#ifndef _HEXASTORE_TYPES_H
#define _HEXASTORE_TYPES_H

#include <stdint.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

#define HEAD_LIST_ALLOC_SIZE				4096
#define VECTOR_LIST_ALLOC_SIZE				64
#define TERMINAL_LIST_ALLOC_SIZE			32

typedef int64_t list_size_t;
typedef int64_t hx_node_id;
typedef struct {
	hx_node_id subject;
	hx_node_id predicate;
	hx_node_id object;
} hx_triple;

typedef struct {
	int (*finished) ( void* iter );
	int (*current) ( void* iter, void* results );
	int (*next) ( void* iter );	
	int (*free) ( void* iter );
} hx_iter_vtable;

#define HX_SUBJECT		0
#define HX_PREDICATE	1
#define HX_OBJECT		2

static char* HX_POSITION_NAMES[3]	= { "SUBJECT", "PREDICATE", "OBJECT" };

#endif
