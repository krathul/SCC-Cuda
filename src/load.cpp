#include "load.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <vector>
using namespace std;

bool mycomp(pair<int, int> a, pair<int, int> b)
{
    return (a.first < b.first || (a.first == b.first && a.second < b.second));
}

void loadFullGraph(const char* filename, int vertices, int edges, uint32_t* oCSize, uint32_t* oRSize, uint32_t** oFc, uint32_t** oFr, uint32_t** oBc, uint32_t** oBr)
{

    uint32_t Edges = edges;
    uint32_t Vertices = vertices;
    char tmp[256];
    char tmp_c;
    uint32_t tmp_i, from, to;

    // open the file
    filebuf fb;
    fb.open(filename, ios::in);
    if (!fb.is_open()) {
        printf("Error Reading graph file\n");
        return;
    }
    istream is(&fb);

    vector<pair<int, int>> edgeList;
    // pair<int, int> p;
    int src, dst;

    for (unsigned int k = 0; k < Edges; k++) {
        is >> src >> dst;
        // is >> p.first >> p.second;
        edgeList.push_back({ src + 1, dst + 1 });
    }

    sort(edgeList.begin(), edgeList.end(), mycomp);

    uint32_t CSize = Edges;
    uint32_t RSize = Vertices + 2;

    uint32_t* Fc = new uint32_t[CSize];
    uint32_t* Fr = new uint32_t[RSize];

    Fr[0] = 0;
    Fr[1] = 0;

    // obtain Fc, Fr
    uint32_t i = 1, j = 0;

    // cout<< "Reading the file" << endl;
    while (j < Edges) {
        from = edgeList[j].first;
        to = edgeList[j].second;

        while (from > i) {
            Fr[i + 1] = j;
            i++;
        }
        Fc[j] = to;
        j++;
    }

    // Fill up remaining indexes with M
    for (uint32_t k = i + 1; k < RSize; k++)
        Fr[k] = j;

    // transposition
    uint32_t* Bc = new uint32_t[CSize];
    uint32_t* Br = new uint32_t[RSize];

    uint32_t* shift = new uint32_t[RSize];

    uint32_t target_vertex = 0, source_vertex = 0;

    for (unsigned int i = 0; i < RSize; i++) {
        Br[i] = 0;
        shift[i] = 0;
    }

    for (unsigned int i = 0; i < CSize; i++) {
        Br[Fc[i] + 1]++;
    }

    for (unsigned int i = 0; i < RSize - 1; i++) {
        Br[i + 1] = Br[i] + Br[i + 1];
    }

    for (unsigned int i = 0; i < CSize; i++) {
        while (i >= Fr[target_vertex + 1]) {
            target_vertex++;
        }
        source_vertex = Fc[i];
        Bc[Br[source_vertex] + shift[source_vertex]] = target_vertex;
        shift[source_vertex]++;
    }
    delete[] shift;

    *oCSize = Edges;
    *oRSize = Vertices;
    *oFc = Fc;
    *oFr = Fr;
    *oBc = Bc;
    *oBr = Br;
}
