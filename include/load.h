#ifndef LOAD_H
#define LOAD_H

#include <stdint.h>

void loadFullGraph(const char* filename, int vertices, int edges, uint32_t* oCSize, uint32_t* oRSize, uint32_t** oFc, uint32_t** oFr, uint32_t** oBc, uint32_t** oBr);

#endif
