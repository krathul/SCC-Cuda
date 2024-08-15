#include "load.h"
#include "scc.h"
#include "scc_kernels.h"
#include <stack>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
using namespace std;

void print_help()
{
    printf("To execute:\n");
    printf("./scc -a [g/h/x/y] -p -q -w [1/2/4/8/16/32] <file> <vertices> <edges>\n");
    printf("-a algorith to use   g - vHong, h - vSlota, x - wHong, y - wSlota\n");
    printf("-p Trim-1 enable\n");
    printf("-q Trim-2 enable\n");
    printf("-w warp size\n");
    return;
}

int main(int argc, char** argv)
{
    char algo;
    int warpSize;
    char file[100];
    bool trim1, trim2;
    int vertices, edges;

    int pflg = 0;
    int qflg = 0;
    int c;

    while ((c = getopt(argc, argv, ":pqw:a:")) != -1) {
        switch (c) {
        case 'p':
            pflg = 1;
            break;
        case 'q':
            qflg = 1;
            break;
        case 'w':
            warpSize = atoi(optarg);
            break;
        case 'a':
            algo = optarg[0];
            break;
        }
    }

    trim1 = (bool)pflg;
    trim2 = (bool)qflg;
    strcpy(file, argv[optind++]);
    vertices = atoi(argv[optind++]);
    edges = atoi(argv[optind]);

    // CSR representation
    uint32_t CSize; // column arrays size
    uint32_t RSize; // range arrays size
    // Forwards arrays
    uint32_t* Fc = NULL; // forward columns
    uint32_t* Fr = NULL; // forward ranges
    // Backwards arrays
    uint32_t* Bc = NULL; // backward columns
    uint32_t* Br = NULL; // backward ranges

    // obtain a CSR graph representation
    loadFullGraph(file, vertices, edges, &CSize, &RSize, &Fc, &Fr, &Bc, &Br);

    try {

        switch (algo) {
        case 'g':
            vHong(CSize, RSize, Fc, Fr, Bc, Br, trim1, trim2);
            break;

        case 'h':
            vSlota(CSize, RSize, Fc, Fr, Bc, Br, trim1, trim2);
            break;

        case 'x':
            wHong(CSize, RSize, Fc, Fr, Bc, Br, trim1, trim2, warpSize);
            break;

        case 'y':
            wSlota(CSize, RSize, Fc, Fr, Bc, Br, trim1, trim2, warpSize);
            break;

        default:
            print_help();
            return 1;
        }
    } catch (const char* e) {
        printf("%s\n", e);
        return 1;
    }
    printf("\n");
    delete[] Fr;
    delete[] Fc;
    delete[] Br;
    delete[] Bc;
    return 0;
}
