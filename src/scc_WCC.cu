#include "scc.h"
#include "scc_kernels.h"
using namespace std;

void wHong(uint32_t CSize, uint32_t RSize, uint32_t *Fc, uint32_t *Fr, uint32_t * Bc, uint32_t * Br, bool t1, bool t2, int warpSize){
    //Set the device which exclusively used by this program
    cudaSetDevice(7);

    float sccTime=0;
    cudaEvent_t sccTimeStart, sccTimeStop;
    cudaEventCreate(&sccTimeStart);
    cudaEventCreate(&sccTimeStop);
    cudaEventRecord(sccTimeStart, 0);

//-----------GPU initialization---------------------------->
    uint32_t* d_Fr = NULL;
    uint32_t* d_Br = NULL;
    uint32_t* d_Fc = NULL;
    uint32_t* d_Bc = NULL;
    uint32_t* d_pivots = NULL;

    uint32_t* d_range = NULL;
    uint8_t* d_tags = NULL;
    uint8_t* tags = new uint8_t[RSize+1];

    bool volatile* d_terminatef = NULL;
    bool terminatef = false;

    bool volatile* d_terminateb = NULL;
    bool terminateb = false;

    int FWD_iterations = 0;
    int BWD_iterations = 0;
    uint32_t iterations = 0;
    int Trimm_iterations = 0;

    const uint32_t max_pivot_count = RSize;

    cudaError_t e1, e2, e3, e4, e5, e6, e7, e8, e9;
    CUDA_SAFE_CALL( e1 = cudaMalloc( (void**) &d_Fc, CSize * sizeof(uint32_t) ));
    CUDA_SAFE_CALL( e2 = cudaMalloc( (void**) &d_Fr, (RSize + 2) * sizeof(uint32_t) ));
    CUDA_SAFE_CALL( e3 = cudaMalloc( (void**) &d_Bc, CSize * sizeof(uint32_t) ));
    CUDA_SAFE_CALL( e4 = cudaMalloc( (void**) &d_Br, (RSize + 2) * sizeof(uint32_t) ));
    CUDA_SAFE_CALL( e5 = cudaMalloc( (void**) &d_range,  (RSize + 1) * sizeof(uint32_t)));
    CUDA_SAFE_CALL( e6 = cudaMalloc( (void**) &d_tags,  (RSize + 1) * sizeof(uint8_t)));
    CUDA_SAFE_CALL( e7 = cudaMalloc( (void**) &d_pivots, max_pivot_count * sizeof(uint32_t) ));
    CUDA_SAFE_CALL( e8 = cudaMalloc( (void**) &d_terminatef, sizeof(bool) ));
    CUDA_SAFE_CALL( e9 = cudaMalloc( (void**) &d_terminateb, sizeof(bool) ));

    if (e1 == cudaErrorMemoryAllocation || e2 == cudaErrorMemoryAllocation ||
        e3 == cudaErrorMemoryAllocation || e4 == cudaErrorMemoryAllocation ||
        e5 == cudaErrorMemoryAllocation || e6 == cudaErrorMemoryAllocation ||
        e7 == cudaErrorMemoryAllocation || e8 == cudaErrorMemoryAllocation || e9 == cudaErrorMemoryAllocation) {
        throw "Error: Not enough memory on GPU\n";
    }

    CUDA_SAFE_CALL( cudaMemcpy( d_Fc, Fc, CSize * sizeof(uint32_t), cudaMemcpyHostToDevice ));
    CUDA_SAFE_CALL( cudaMemcpy( d_Fr, Fr, (RSize + 2) * sizeof(uint32_t), cudaMemcpyHostToDevice ));
    CUDA_SAFE_CALL( cudaMemcpy( d_Bc, Bc, CSize * sizeof(uint32_t), cudaMemcpyHostToDevice ));
    CUDA_SAFE_CALL( cudaMemcpy( d_Br, Br, (RSize + 2) * sizeof(uint32_t), cudaMemcpyHostToDevice ));
    
    CUDA_SAFE_CALL( cudaMemset( d_range, 0, (RSize + 1) * sizeof(uint32_t)));
    CUDA_SAFE_CALL( cudaMemset( d_tags, 0, (RSize + 1) * sizeof(uint8_t)));

    dim3 gridfb;
    if((RSize * warpSize + BLOCKSIZE - 1)/BLOCKSIZE > MaxXDimOfGrid) {
        int dim = ceill(sqrt(RSize * warpSize / BLOCKSIZE));
        gridfb.x = dim;
        gridfb.y = dim;
        gridfb.z = 1;
    }else{
        gridfb.x = (RSize * warpSize + BLOCKSIZE - 1)/BLOCKSIZE;
        gridfb.y = 1;
        gridfb.z = 1;
    }

    //for vertex-to-thread mapping
    dim3 grid;
    if((RSize + BLOCKSIZE - 1)/BLOCKSIZE > MaxXDimOfGrid) {
        int dim = ceill(sqrt(RSize / BLOCKSIZE));
        grid.x = dim;
        grid.y = dim;
        grid.z = 1;
    }else{
        grid.x = (RSize + BLOCKSIZE - 1)/BLOCKSIZE;
        grid.y = 1;
        grid.z = 1;
    }


    dim3 threads(BLOCKSIZE, 1, 1);

#ifdef _DEBUG
float pivotTime = 0, temp = 0, bTime = 0, trim1Time = 0, trim2Time = 0, updateTime = 0, wccTime = 0;
cudaEvent_t bTimeStart, bTimeStop, pivotTimeStart, pivotTimeStop, updateTimeStart, updateTimeStop;
cudaEvent_t trim1TimeStart, trim1TimeStop, trim2TimeStart, trim2TimeStop, wccTimeStart, wccTimeStop;

cudaEventCreate(&bTimeStart);
cudaEventCreate(&bTimeStop);

cudaEventCreate(&pivotTimeStart);
cudaEventCreate(&pivotTimeStop);

cudaEventCreate(&trim1TimeStart);
cudaEventCreate(&trim1TimeStop);

cudaEventCreate(&trim2TimeStart);
cudaEventCreate(&trim2TimeStop);

cudaEventCreate(&updateTimeStart);
cudaEventCreate(&updateTimeStop);

cudaEventCreate(&wccTimeStart);
cudaEventCreate(&wccTimeStop);
#endif


#ifdef _DEBUG
cudaEventRecord(trim1TimeStart, 0);
#endif

//-----------Trimming-------------------------------------->
        if(t1){
            do {
                Trimm_iterations++;
                CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
                trim1<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize, d_terminatef);
                CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            } while (!terminatef);
        }

#ifdef _DEBUG
cudaEventRecord(trim1TimeStop, 0);
cudaEventSynchronize(trim1TimeStop);
cudaEventElapsedTime(&temp, trim1TimeStart, trim1TimeStop);
trim1Time+=temp;
#endif

//-----------Choose pivots--------------------------------->
#ifdef _DEBUG
cudaEventRecord(pivotTimeStart, 0);
#endif

        CUDA_SAFE_CALL( cudaMemset( d_pivots, 0, sizeof(uint32_t) ));
        pollForFirstPivot<<<grid, threads>>>( d_tags, RSize, d_pivots, d_Fr, d_Br);
        selectFirstPivot<<<grid, threads>>>( d_tags, RSize, d_pivots);

#ifdef _DEBUG
cudaEventRecord(pivotTimeStop, 0);
cudaEventSynchronize(pivotTimeStop);

cudaEventElapsedTime(&temp, pivotTimeStart, pivotTimeStop);
pivotTime+=temp;
#endif


#ifdef _DEBUG
cudaEventRecord(bTimeStart, 0);
#endif

        do{//Forward and Backward reachability
            FWD_iterations++;
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));

            switch(warpSize){
                case 1:
                    fwd_warp<1><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    bwd_warp<1><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 2:
                    fwd_warp<2><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    bwd_warp<2><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 4:
                    fwd_warp<4><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    bwd_warp<4><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 8:
                    fwd_warp<8><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    bwd_warp<8><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 16:
                    fwd_warp<16><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    bwd_warp<16><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 32:
                    fwd_warp<32><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    bwd_warp<32><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;
            }

            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }while(!terminatef && !terminateb);

        while(!terminatef){//Forward reachability
            FWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            switch(warpSize){
                case 1:
                    fwd_warp<1><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    break;

                case 2:
                    fwd_warp<2><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    break;

                case 4:
                    fwd_warp<4><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    break;

                case 8:
                    fwd_warp<8><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    break;

                case 16:
                    fwd_warp<16><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    break;

                case 32:
                    fwd_warp<32><<<gridfb, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
                    break;
            }

            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        }

         while(!terminateb){//Backward reachability
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));

            switch(warpSize){
                case 1:
                    bwd_warp<1><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 2:
                    bwd_warp<2><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 4:
                    bwd_warp<4><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 8:
                    bwd_warp<8><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 16:
                    bwd_warp<16><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;

                case 32:
                    bwd_warp<32><<<gridfb, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
                    break;
            }

            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }

#ifdef _DEBUG
cudaEventRecord(bTimeStop, 0);
cudaEventSynchronize(bTimeStop);

cudaEventElapsedTime(&temp, bTimeStart, bTimeStop);
bTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(updateTimeStart, 0);
#endif

        update<<<grid, threads>>>(d_range, d_tags, RSize, d_terminatef);

#ifdef _DEBUG
cudaEventRecord(updateTimeStop, 0);
cudaEventSynchronize(updateTimeStop);

cudaEventElapsedTime(&temp, updateTimeStart, updateTimeStop);
updateTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(trim1TimeStart, 0);
#endif

//-----------Trimming-------------------------------------->
        if(t1){
            do {
                Trimm_iterations++;
                CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
                trim1<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize, d_terminatef);
                CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            } while (!terminatef);
        }

#ifdef _DEBUG
cudaEventRecord(trim1TimeStop, 0);
cudaEventSynchronize(trim1TimeStop);
cudaEventElapsedTime(&temp, trim1TimeStart, trim1TimeStop);
trim1Time+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(trim2TimeStart, 0);
#endif
        if(t2)
            trim2<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize);

#ifdef _DEBUG
cudaEventRecord(trim2TimeStop, 0);
cudaEventSynchronize(trim2TimeStop);
cudaEventElapsedTime(&temp, trim2TimeStart, trim2TimeStop);
trim2Time+=temp;
#endif


#ifdef _DEBUG
cudaEventRecord(trim1TimeStart, 0);
#endif

//-----------Trimming-------------------------------------->
        if(t1){
            do {
                Trimm_iterations++;
                CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
                trim1<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize, d_terminatef);
                CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            } while (!terminatef);
        }

#ifdef _DEBUG
cudaEventRecord(trim1TimeStop, 0);
cudaEventSynchronize(trim1TimeStop);
cudaEventElapsedTime(&temp, trim1TimeStart, trim1TimeStop);
trim1Time+=temp;
#endif


#ifdef _DEBUG
cudaEventRecord(wccTimeStart, 0);
#endif

//Now WCC decomposition
    assignUniqueRange<<<grid, threads>>>(d_range, d_tags, RSize);

    do{
        CUDA_SAFE_CALL( cudaMemset((void *)d_terminatef, true, sizeof(bool) ));
        propagateRange1<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
        CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        
        CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
        propagateRange2<<<grid, threads>>>( d_range, d_tags, RSize, d_terminateb);
        CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
    }while(!terminatef || !terminateb);


#ifdef _DEBUG
cudaEventRecord(wccTimeStop, 0);
cudaEventSynchronize(wccTimeStop);
cudaEventElapsedTime(&temp, wccTimeStart, wccTimeStop);
wccTime+=temp;
#endif

//-----------Main algorithm-------------------------------->
    while ( true ) {
        iterations++;
        //cout<<"\nIteration : "<<iterations<<endl;

//-----------Choose pivots--------------------------------->
#ifdef _DEBUG
cudaEventRecord(pivotTimeStart, 0);
#endif

        CUDA_SAFE_CALL( cudaMemset( d_pivots, 0,  max_pivot_count * sizeof(uint32_t) ));
        pollForPivots<<<grid, threads>>>( d_range, d_tags, RSize, d_pivots, max_pivot_count, d_Fr, d_Br);
        selectPivots<<<grid, threads>>>( d_range, d_tags, RSize, d_pivots, max_pivot_count);

#ifdef _DEBUG
cudaEventRecord(pivotTimeStop, 0);
cudaEventSynchronize(pivotTimeStop);

cudaEventElapsedTime(&temp, pivotTimeStart, pivotTimeStop);
pivotTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(bTimeStart, 0);
#endif

        do{//Forward and Backward reachability
            FWD_iterations++;
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
            fwd<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
            bwd<<<grid, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }while(!terminatef && !terminateb);

        while(!terminatef){//Forward reachability
            FWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            fwd<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        }

         while(!terminateb){//Backward reachability
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
            bwd<<<grid, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }


#ifdef _DEBUG
cudaEventRecord(bTimeStop, 0);
cudaEventSynchronize(bTimeStop);

cudaEventElapsedTime(&temp, bTimeStart, bTimeStop);
bTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(updateTimeStart, 0);
#endif

        CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
        update<<<grid, threads>>>(d_range, d_tags, RSize, d_terminatef);
        CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        if (terminatef)
            break; //only way out

#ifdef _DEBUG
cudaEventRecord(updateTimeStop, 0);
cudaEventSynchronize(updateTimeStop);

cudaEventElapsedTime(&temp, updateTimeStart, updateTimeStop);
updateTime+=temp;
#endif
    }
//<----------Main algorithm---------------------------------

    //SCC extraction
    CUDA_SAFE_CALL( cudaMemcpy(tags, d_tags, sizeof(uint8_t) * (RSize + 1), cudaMemcpyDeviceToHost ));
    uint32_t numberOf1Sccs = 0;
    uint32_t numberOf2Sccs = 0;
    uint32_t numberOfPivotSccs = 0;
    uint32_t numberOfSccs = 0;

    for(uint32_t i=1;i<=RSize;i++)
        if(isTrim1(tags[i]))
            numberOf1Sccs++;
        else if(isTrim2(tags[i]))
            numberOf2Sccs++;
        else if(isPivot(tags[i]))
            numberOfPivotSccs++;

    numberOfSccs = numberOf1Sccs + numberOf2Sccs + numberOfPivotSccs;

    cudaEventRecord(sccTimeStop, 0);
    cudaEventSynchronize(sccTimeStop);
    cudaEventElapsedTime(&sccTime, sccTimeStart, sccTimeStop);

    //printf(", %u, %d, %d, %d", iterations, FWD_iterations , BWD_iterations, Trimm_iterations);

#ifdef _DEBUG
printf(", %f", bTime);
printf(", %f", trim1Time);
printf(", %f", trim2Time);
printf(", %f", pivotTime);
printf(", %f", updateTime);
printf(", %f", wccTime);
#endif

    printf("\nNumber Of Sccs : %d", numberOfSccs);
    printf("\nTime : %f", sccTime );

    CUDA_SAFE_CALL( cudaFree( d_Fc ));
    CUDA_SAFE_CALL( cudaFree( d_Fr ));
    CUDA_SAFE_CALL( cudaFree( d_Bc ));
    CUDA_SAFE_CALL( cudaFree( d_Br ));
    CUDA_SAFE_CALL( cudaFree( d_range));
    CUDA_SAFE_CALL( cudaFree( d_tags));
    CUDA_SAFE_CALL( cudaFree( d_pivots ));
    CUDA_SAFE_CALL( cudaFree( (void *)d_terminatef));
    CUDA_SAFE_CALL( cudaFree( (void *)d_terminateb));    

    cudaEventDestroy(sccTimeStart);
    cudaEventDestroy(sccTimeStop);

#ifdef _DEBUG
cudaEventDestroy(bTimeStart);
cudaEventDestroy(bTimeStop);
cudaEventDestroy(trim1TimeStart);
cudaEventDestroy(trim1TimeStop);
cudaEventDestroy(trim2TimeStart);
cudaEventDestroy(trim2TimeStop);
cudaEventDestroy(pivotTimeStart);
cudaEventDestroy(pivotTimeStop);
cudaEventDestroy(updateTimeStart);
cudaEventDestroy(updateTimeStop);
cudaEventDestroy(wccTimeStart);
cudaEventDestroy(wccTimeStop);
#endif

    return;
}


void vHong(uint32_t CSize, uint32_t RSize, uint32_t *Fc, uint32_t *Fr, uint32_t * Bc, uint32_t * Br, bool t1, bool t2){
    //Set the device which exclusively used by this program
    cudaSetDevice(7);

    float sccTime=0;
    cudaEvent_t sccTimeStart, sccTimeStop;
    cudaEventCreate(&sccTimeStart);
    cudaEventCreate(&sccTimeStop);
    cudaEventRecord(sccTimeStart, 0);

//-----------GPU initialization---------------------------->
	uint32_t* d_Fr = NULL;
    uint32_t* d_Br = NULL;
	uint32_t* d_Fc = NULL;
    uint32_t* d_Bc = NULL;
    uint32_t* d_pivots = NULL;

	uint32_t* d_range = NULL;
    uint8_t* d_tags = NULL;
    uint8_t* tags = new uint8_t[RSize+1];

    bool volatile* d_terminatef = NULL;
    bool terminatef = false;

    bool volatile* d_terminateb = NULL;
    bool terminateb = false;

	int FWD_iterations = 0;
    int BWD_iterations = 0;
	uint32_t iterations = 0;
	int Trimm_iterations = 0;

    const uint32_t max_pivot_count = RSize;

	cudaError_t e1, e2, e3, e4, e5, e6, e7, e8;
	CUDA_SAFE_CALL( e1 = cudaMalloc( (void**) &d_Fc, CSize * sizeof(uint32_t) ));
	CUDA_SAFE_CALL( e2 = cudaMalloc( (void**) &d_Fr, (RSize + 2) * sizeof(uint32_t) ));
	CUDA_SAFE_CALL( e3 = cudaMalloc( (void**) &d_Bc, CSize * sizeof(uint32_t) ));
	CUDA_SAFE_CALL( e4 = cudaMalloc( (void**) &d_Br, (RSize + 2) * sizeof(uint32_t) ));
	CUDA_SAFE_CALL( e5 = cudaMalloc( (void**) &d_range,  (RSize + 1) * sizeof(uint32_t)));
    CUDA_SAFE_CALL( e5 = cudaMalloc( (void**) &d_tags,  (RSize + 1) * sizeof(uint8_t)));
    CUDA_SAFE_CALL( e6 = cudaMalloc( (void**) &d_pivots, max_pivot_count * sizeof(uint32_t) ));
    CUDA_SAFE_CALL( e7 = cudaMalloc( (void**) &d_terminatef, sizeof(bool) ));
    CUDA_SAFE_CALL( e8 = cudaMalloc( (void**) &d_terminateb, sizeof(bool) ));

	if (e1 == cudaErrorMemoryAllocation || e2 == cudaErrorMemoryAllocation ||
		e3 == cudaErrorMemoryAllocation || e4 == cudaErrorMemoryAllocation ||
		e5 == cudaErrorMemoryAllocation || e6 == cudaErrorMemoryAllocation ||
        e7 == cudaErrorMemoryAllocation || e8 == cudaErrorMemoryAllocation ) {
		throw "Error: Not enough memory on GPU\n";
	}

	CUDA_SAFE_CALL( cudaMemcpy( d_Fc, Fc, CSize * sizeof(uint32_t), cudaMemcpyHostToDevice ));
	CUDA_SAFE_CALL( cudaMemcpy( d_Fr, Fr, (RSize + 2) * sizeof(uint32_t), cudaMemcpyHostToDevice ));
	CUDA_SAFE_CALL( cudaMemcpy( d_Bc, Bc, CSize * sizeof(uint32_t), cudaMemcpyHostToDevice ));
	CUDA_SAFE_CALL( cudaMemcpy( d_Br, Br, (RSize + 2) * sizeof(uint32_t), cudaMemcpyHostToDevice ));
	
    CUDA_SAFE_CALL( cudaMemset( d_range, 0, (RSize + 1) * sizeof(uint32_t)));
    CUDA_SAFE_CALL( cudaMemset( d_tags, 0, (RSize + 1) * sizeof(uint8_t)));

    //for vertex-to-thread mapping
    dim3 grid;
    if((RSize + BLOCKSIZE - 1)/BLOCKSIZE > MaxXDimOfGrid) {
        int dim = ceill(sqrt(RSize / BLOCKSIZE));
        grid.x = dim;
        grid.y = dim;
        grid.z = 1;
    }else{
        grid.x = (RSize + BLOCKSIZE - 1)/BLOCKSIZE;
        grid.y = 1;
        grid.z = 1;
    }


	dim3 threads(BLOCKSIZE, 1, 1);


#ifdef _DEBUG
float pivotTime = 0, temp = 0, bTime = 0, trim1Time = 0, trim2Time = 0, updateTime = 0, wccTime = 0;
cudaEvent_t bTimeStart, bTimeStop, pivotTimeStart, pivotTimeStop, updateTimeStart, updateTimeStop;
cudaEvent_t trim1TimeStart, trim1TimeStop, trim2TimeStart, trim2TimeStop, wccTimeStart, wccTimeStop;

cudaEventCreate(&bTimeStart);
cudaEventCreate(&bTimeStop);

cudaEventCreate(&pivotTimeStart);
cudaEventCreate(&pivotTimeStop);

cudaEventCreate(&trim1TimeStart);
cudaEventCreate(&trim1TimeStop);

cudaEventCreate(&trim2TimeStart);
cudaEventCreate(&trim2TimeStop);

cudaEventCreate(&updateTimeStart);
cudaEventCreate(&updateTimeStop);

cudaEventCreate(&wccTimeStart);
cudaEventCreate(&wccTimeStop);
#endif


#ifdef _DEBUG
cudaEventRecord(trim1TimeStart, 0);
#endif

//-----------Trimming-------------------------------------->
        if(t1){
            do {
                Trimm_iterations++;
                CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
                trim1<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize, d_terminatef);
                CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            } while (!terminatef);
        }

#ifdef _DEBUG
cudaEventRecord(trim1TimeStop, 0);
cudaEventSynchronize(trim1TimeStop);
cudaEventElapsedTime(&temp, trim1TimeStart, trim1TimeStop);
trim1Time+=temp;
#endif

//-----------Choose pivots--------------------------------->
#ifdef _DEBUG
cudaEventRecord(pivotTimeStart, 0);
#endif

        CUDA_SAFE_CALL( cudaMemset( d_pivots, 0, sizeof(uint32_t) ));
        pollForFirstPivot<<<grid, threads>>>( d_tags, RSize, d_pivots, d_Fr, d_Br);
        selectFirstPivot<<<grid, threads>>>( d_tags, RSize, d_pivots);

#ifdef _DEBUG
cudaEventRecord(pivotTimeStop, 0);
cudaEventSynchronize(pivotTimeStop);

cudaEventElapsedTime(&temp, pivotTimeStart, pivotTimeStop);
pivotTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(bTimeStart, 0);
#endif

        do{//Forward and Backward reachability
            FWD_iterations++;
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
            fwd<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
            bwd<<<grid, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }while(!terminatef && !terminateb);

        while(!terminatef){//Forward reachability
            FWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            fwd<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        }

         while(!terminateb){//Backward reachability
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
            bwd<<<grid, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }


#ifdef _DEBUG
cudaEventRecord(bTimeStop, 0);
cudaEventSynchronize(bTimeStop);

cudaEventElapsedTime(&temp, bTimeStart, bTimeStop);
bTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(updateTimeStart, 0);
#endif

        update<<<grid, threads>>>(d_range, d_tags, RSize, d_terminatef);

#ifdef _DEBUG
cudaEventRecord(updateTimeStop, 0);
cudaEventSynchronize(updateTimeStop);

cudaEventElapsedTime(&temp, updateTimeStart, updateTimeStop);
updateTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(trim1TimeStart, 0);
#endif

//-----------Trimming-------------------------------------->
        if(t1){
            do {
                Trimm_iterations++;
                CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
                trim1<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize, d_terminatef);
                CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            } while (!terminatef);
        }

#ifdef _DEBUG
cudaEventRecord(trim1TimeStop, 0);
cudaEventSynchronize(trim1TimeStop);
cudaEventElapsedTime(&temp, trim1TimeStart, trim1TimeStop);
trim1Time+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(trim2TimeStart, 0);
#endif
        if(t2)
            trim2<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize);

#ifdef _DEBUG
cudaEventRecord(trim2TimeStop, 0);
cudaEventSynchronize(trim2TimeStop);
cudaEventElapsedTime(&temp, trim2TimeStart, trim2TimeStop);
trim2Time+=temp;
#endif


#ifdef _DEBUG
cudaEventRecord(trim1TimeStart, 0);
#endif

//-----------Trimming-------------------------------------->
        if(t1){
            do {
                Trimm_iterations++;
                CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
                trim1<<<grid, threads>>>( d_range, d_tags, d_Fc, d_Fr, d_Bc, d_Br, RSize, d_terminatef);
                CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            } while (!terminatef);
        }

#ifdef _DEBUG
cudaEventRecord(trim1TimeStop, 0);
cudaEventSynchronize(trim1TimeStop);
cudaEventElapsedTime(&temp, trim1TimeStart, trim1TimeStop);
trim1Time+=temp;
#endif


#ifdef _DEBUG
cudaEventRecord(wccTimeStart, 0);
#endif

//Now WCC decomposition
    assignUniqueRange<<<grid, threads>>>(d_range, d_tags, RSize);

    do{
        CUDA_SAFE_CALL( cudaMemset((void *)d_terminatef, true, sizeof(bool) ));
        propagateRange1<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
        CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        
        CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
        propagateRange2<<<grid, threads>>>( d_range, d_tags, RSize, d_terminateb);
        CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
    }while(!terminatef || !terminateb);


#ifdef _DEBUG
cudaEventRecord(wccTimeStop, 0);
cudaEventSynchronize(wccTimeStop);
cudaEventElapsedTime(&temp, wccTimeStart, wccTimeStop);
wccTime+=temp;
#endif

//-----------Main algorithm-------------------------------->
	while ( true ) {
		iterations++;
        //cout<<"\nIteration : "<<iterations<<endl;

//-----------Choose pivots--------------------------------->
#ifdef _DEBUG
cudaEventRecord(pivotTimeStart, 0);
#endif

        CUDA_SAFE_CALL( cudaMemset( d_pivots, 0,  max_pivot_count * sizeof(uint32_t) ));
        pollForPivots<<<grid, threads>>>( d_range, d_tags, RSize, d_pivots, max_pivot_count, d_Fr, d_Br);
        selectPivots<<<grid, threads>>>( d_range, d_tags, RSize, d_pivots, max_pivot_count);

#ifdef _DEBUG
cudaEventRecord(pivotTimeStop, 0);
cudaEventSynchronize(pivotTimeStop);

cudaEventElapsedTime(&temp, pivotTimeStart, pivotTimeStop);
pivotTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(bTimeStart, 0);
#endif

        do{//Forward and Backward reachability
            FWD_iterations++;
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
            fwd<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
            bwd<<<grid, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }while(!terminatef && !terminateb);

        while(!terminatef){//Forward reachability
            FWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
            fwd<<<grid, threads>>>( d_Fc, d_Fr, d_range, d_tags, RSize, d_terminatef);
            CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        }

         while(!terminateb){//Backward reachability
            BWD_iterations++;

            CUDA_SAFE_CALL( cudaMemset((void *)d_terminateb, true, sizeof(bool) ));
            bwd<<<grid, threads>>>( d_Bc, d_Br, d_range, d_tags, RSize, d_terminateb);
            CUDA_SAFE_CALL( cudaMemcpy( &terminateb, (const void *)d_terminateb, sizeof(bool), cudaMemcpyDeviceToHost ));
        }


#ifdef _DEBUG
cudaEventRecord(bTimeStop, 0);
cudaEventSynchronize(bTimeStop);

cudaEventElapsedTime(&temp, bTimeStart, bTimeStop);
bTime+=temp;
#endif

#ifdef _DEBUG
cudaEventRecord(updateTimeStart, 0);
#endif

        CUDA_SAFE_CALL( cudaMemset( (void *)d_terminatef, true, sizeof(bool) ));
        update<<<grid, threads>>>(d_range, d_tags, RSize, d_terminatef);
        CUDA_SAFE_CALL( cudaMemcpy( &terminatef, (const void *)d_terminatef, sizeof(bool), cudaMemcpyDeviceToHost ));
        if (terminatef)
            break; //only way out

#ifdef _DEBUG
cudaEventRecord(updateTimeStop, 0);
cudaEventSynchronize(updateTimeStop);

cudaEventElapsedTime(&temp, updateTimeStart, updateTimeStop);
updateTime+=temp;
#endif
	}
//<----------Main algorithm---------------------------------

    //SCC extraction
    CUDA_SAFE_CALL( cudaMemcpy(tags, d_tags, sizeof(uint8_t) * (RSize + 1), cudaMemcpyDeviceToHost ));
    uint32_t numberOf1Sccs = 0;
    uint32_t numberOf2Sccs = 0;
    uint32_t numberOfPivotSccs = 0;
    uint32_t numberOfSccs = 0;

    for(uint32_t i=1;i<=RSize;i++)
        if(isTrim1(tags[i]))
            numberOf1Sccs++;
        else if(isTrim2(tags[i]))
            numberOf2Sccs++;
        else if(isPivot(tags[i]))
            numberOfPivotSccs++;

    numberOfSccs = numberOf1Sccs + numberOf2Sccs + numberOfPivotSccs;

	cudaEventRecord(sccTimeStop, 0);
    cudaEventSynchronize(sccTimeStop);
    cudaEventElapsedTime(&sccTime, sccTimeStart, sccTimeStop);

    //printf(", %u, %d, %d, %d", iterations, FWD_iterations , BWD_iterations, Trimm_iterations);

#ifdef _DEBUG
printf(", %f", bTime);
printf(", %f", trim1Time);
printf(", %f", trim2Time);
printf(", %f", pivotTime);
printf(", %f", updateTime);
printf(", %f", wccTime);
#endif

    printf("\nNumber Of Sccs : %d", numberOfSccs);
    printf("\nTime : %f", sccTime );

	CUDA_SAFE_CALL( cudaFree( d_Fc ));
	CUDA_SAFE_CALL( cudaFree( d_Fr ));
	CUDA_SAFE_CALL( cudaFree( d_Bc ));
	CUDA_SAFE_CALL( cudaFree( d_Br ));
	CUDA_SAFE_CALL( cudaFree( d_range));
    CUDA_SAFE_CALL( cudaFree( d_tags));
	CUDA_SAFE_CALL( cudaFree( d_pivots ));
	CUDA_SAFE_CALL( cudaFree( (void *)d_terminatef));
    CUDA_SAFE_CALL( cudaFree( (void *)d_terminateb));

	cudaEventDestroy(sccTimeStart);
    cudaEventDestroy(sccTimeStop);

#ifdef _DEBUG
cudaEventDestroy(bTimeStart);
cudaEventDestroy(bTimeStop);
cudaEventDestroy(trim1TimeStart);
cudaEventDestroy(trim1TimeStop);
cudaEventDestroy(trim2TimeStart);
cudaEventDestroy(trim2TimeStop);
cudaEventDestroy(pivotTimeStart);
cudaEventDestroy(pivotTimeStop);
cudaEventDestroy(updateTimeStart);
cudaEventDestroy(updateTimeStop);
cudaEventDestroy(wccTimeStart);
cudaEventDestroy(wccTimeStop);
#endif

	return;
}
