/*
  Copyright 2016 Google Inc. All Rights Reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
      http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/

#define STACK_SIZE 8192 // 8192 * 4 bytes = 32768 bytes stack
#define NULL (void*)0
#define PAGE_SIZE 65536

// Exploit the fact that we know about the internals of binaryen to set the
// stack correctly. The name __stack_pointer is special in LLVM.
unsigned stack[STACK_SIZE];
unsigned* __stack_pointer = &stack[STACK_SIZE - 1];

void* malloc(unsigned size);
void free(void* ptr);
// void* realloc(void* ptr, unsigned int size);
unsigned grow_memory(unsigned delta);

struct header {
  struct header *ptr;
  unsigned size;
};

typedef struct header Header;

static Header* morecore(unsigned size);

static Header base; // empty initial free list
static Header *freep = NULL; // pointer to free list

void* malloc(unsigned size) {
  Header *p, *prevp;
  unsigned units;

  units = (size + sizeof(Header) - 1) / sizeof(Header) + 1;
  if ((prevp = freep) == NULL) {
    base.ptr = freep = prevp = &base;
    base.size = 0;
  }
  for (p = prevp->ptr; ; prevp = p, p = p->ptr) {
    if (p->size >= units) { /* big enough */
      if (p->size == units) {/* exactly */
        prevp->ptr = p->ptr;
      } else { /* allocate tail end */
        p->size -= units;
        p += p->size;
        p->size = units;
      }
      freep = prevp;
      return (void*)(p + 1);
    }
    if (p == freep) {/* wrapped around free list */
      if ((p = morecore(units)) == NULL) {
        return NULL; /* none left */
      }
    }
  }
}

static Header* morecore(unsigned size) {
  int current_page;
  Header* up;
  int pages = ((size * sizeof(Header)) >> 16) + 1; // We can only request full pages from grow_memory
  current_page = grow_memory(pages);
  if (current_page == -1) /* no space at all */
    return NULL;

  up = (Header*)(current_page * PAGE_SIZE);
  up->size = pages * PAGE_SIZE / sizeof(Header);
  free((void*)(up + 1));
  return freep;
}

int allocated_pages = 1;

unsigned grow_memory(unsigned delta) {
  int result;
  asm("grow_memory %0=, %1" : "=r"(result) : "r"(delta) : "memory");
  allocated_pages += delta;
  return result;
}

void free(void * ap) {
  Header *bp, *p;
  bp = (Header*)ap - 1; /* point to block header */
  for (p = freep; !(bp > p && bp < p->ptr); p = p->ptr) {
    if (p >= p->ptr && (bp > p || bp < p->ptr)) {
      break; /* freed block at start or end of arena */
    }
  }

  if (bp + bp->size == p->ptr) { /* join to upper nbr */
    bp->size += p->ptr->size;
    bp->ptr = p->ptr->ptr;
  } else {
    bp->ptr = p->ptr;
  }

  if (p + p->size == bp) { /* join to lower nbr */
    p->size += bp->size;
    p->ptr = bp->ptr;
  } else {
    p->ptr = bp;
  }

  freep = p;
}
