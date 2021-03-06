
// includes, system
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <complex.h>

// includes, project
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <cufft.h>
#include <cuComplex.h>
#include <helper_functions.h>
#include <helper_cuda.h>
#include <timer.h>
#include <cuda_profiler_api.h>

// include parameters for DNS
#include "dnsparams.h"
#include "solver.h"
#include "statistics.h"
#include "cudafuncs.h"
#include "iofuncs.h"
#include "initialize.h"
#include "fftfuncs.h"
#include "struct_def.h"
#include "declare.h"
#include "allocate.h"

void splitData(int numGPUs, gpudata *gpu) {
	int i, n;
	gpu->nGPUs = numGPUs;

	// Allocate pinned memory on the host that stores GPU info
	cudaHostAlloc((void**)&gpu->gpunum,  numGPUs*sizeof(gpu->gpunum),  cudaHostAllocMapped);
	cudaHostAlloc((void**)&gpu->ny,      numGPUs*sizeof(gpu->ny),      cudaHostAllocMapped);
	cudaHostAlloc((void**)&gpu->nx,      numGPUs*sizeof(gpu->nx),      cudaHostAllocMapped);
	cudaHostAlloc((void**)&gpu->start_y, numGPUs*sizeof(gpu->start_y), cudaHostAllocMapped);
	cudaHostAlloc((void**)&gpu->start_x, numGPUs*sizeof(gpu->start_x), cudaHostAllocMapped);

	// Add numGPUs to each GPU struct:
	for(i=0;i<numGPUs;++i){
		gpu->gpunum[i] = i;
	}

	// Splitting data in x-direction
	if(NX % numGPUs == 0){
		for (i=0; i<numGPUs; ++i){
			gpu->nx[i] = NX/numGPUs;
			gpu->start_x[i] = i*gpu->nx[i];           
		}
	}
	else {
		printf("Warning: number of GPUs is not an even multiple of the data size\n");
		n = NX/numGPUs;
		for(i=0; i<(numGPUs-1); ++i){
			gpu->nx[i] = n;
			gpu->start_x[i] = i*gpu->nx[i];
		}
		gpu->nx[numGPUs-1] = n + NX%numGPUs;
		gpu->start_x[numGPUs-1] = (numGPUs-1)*n;
	}
	// Now splitting data across y-direction
	if(NY % numGPUs == 0){
		for (i=0; i<numGPUs; ++i){
			gpu->ny[i] = NY/numGPUs;
			gpu->start_y[i] = i*gpu->ny[i];           
		}
	}
	else {
		printf("Warning: number of GPUs is not an even multiple of the data size\n");
		n = NY/numGPUs;
		for(i=0; i<(numGPUs-1); ++i){
			gpu->ny[i] = n;
			gpu->start_y[i] = i*gpu->ny[i];
		}
		gpu->ny[numGPUs-1] = n + NY%numGPUs;
		gpu->start_y[numGPUs-1] = (numGPUs-1)*n;
	}
	return;
}

int main (void)
{

//=====================================================================================================
// Program Start-up 
//=====================================================================================================
	// Set GPU's to use and list device properties
	int n, nGPUs;
	// Query number of devices attached to host
	// cudaGetDeviceCount(&nGPUs);
	nGPUs=1;

	printf("Welcome to the GPU-based Navier-Stokes Solver! Configuration: \n"
		"Number of GPUs = %d \n "
		"Grid size = %dx%dx%d \n ",nGPUs,NX,NY,NZ);
	// List properties of each device
	displayDeviceProps(nGPUs);
	
//=====================================================================================================
// Allocate Memory 
//=====================================================================================================
	splitData(nGPUs, &gpu);

	// Variables declared in "declare.h"
	// Allocate memory for variables
	allocate_memory();

  // Create plans for cuFFT on each GPU
  plan1dFFT(nGPUs, fft);
  plan2dFFT(gpu, fft);
  printf("FFT's successfully configured!\n");

	// Declare variables
	int c = 0;
	int euler = 0;
	double time=0.0;
	double steptime=0.0;
	
//=======================================================================================================
// Initialize simulation
//=======================================================================================================

	// printf("Starting Timer...\n");
	// StartTimer();

	// Setup wavespace domain
	initializeWaveNumbers(gpu, grid);

	// Launch CUDA kernel to initialize velocity field
	//importVelocity(gpu, h_vel, vel);
	//importScalar(gpu, h_vel, vel);
	
  //initializeTaylorGreen(gpu,vel);
	//initializeJet_Superposition(fft, gpu, grid, h_vel, vel, rhs);	// Does not require importData
	//init_unit_test(gpu, fft, vel);
	initializeJet(fft, gpu, grid, h_vel, vel, rhs); // Does not require importData

	// Save Initial Data to file (t = 0)
	// Copy data to host   
	save3Dfields(c, fft, gpu, h_vel, vel);
	save2Dfields(c, fft, gpu, h_vel, vel);
	
	synchronizeGPUs(nGPUs);

	// Transform velocity to fourier space for timestepping
	forwardTransform(fft, gpu, vel.u);
	forwardTransform(fft, gpu, vel.v);
	forwardTransform(fft, gpu, vel.w);
	forwardTransform(fft, gpu, vel.s);
	forwardTransform(fft, gpu, vel.c);

	// Dealias the solution by truncating RHS
	deAlias(gpu, grid, vel);

	// Calculate statistics at initial condition
	calcTurbStats_mgpu(0, gpu, fft, grid, vel, rhs, stats, Yprof);
	
	// Synchronize GPUs before entering timestepping loop
	synchronizeGPUs(nGPUs);

	// Print statistics to screen
	int stats_count = 0;
	printTurbStats(stats_count,0.0,stats[0]); // Using 0 index to send aggregate data collected in first index
	stats_count += 1;

	// Start iteration timer
	// StartTimer();
  cudaProfilerStart();
//==================================================================================================
// Enter time-stepping loop
//==================================================================================================
	for ( c = 1; c <= nt; ++c ){
		// Start iteration timer
		StartTimer();

		// Create flags to specify Euler timesteps

		if (c == 1){
			euler = 1;
		}
		else{
			euler = 0;
		}

		// Call pseudospectral Navier-Stokes solver
		solver_ps(euler, fft, gpu, grid, vel, rhs, rhs_old, temp);

		//==============================================================================================
		// Calculate bulk turbulence statistics and print to screen
		//==============================================================================================
		if(c % n_stats == 0){
			calcTurbStats_mgpu(c, gpu, fft, grid, vel, rhs, stats, Yprof);
			// Get elapsed time from Timer
			steptime = GetTimer();
		
			// Print statistics to screen
			printTurbStats(stats_count,steptime,stats[0]);  // Using 0 index to send aggregate data collected in first index
			stats_count += 1;
		}

		if(c % n_vis == 0){
			save2Dfields(c, fft, gpu, h_vel, vel);
		}

		// Synchronize GPUs before moving to next timestep
		synchronizeGPUs(nGPUs);

		// Save data to file every n_checkpoint timesteps
		if ( c % n_checkpoint == 0 ){
			save3Dfields(c, fft, gpu, h_vel, vel);
		}

	//===============================================================================================
	// End of Timestep
	//===============================================================================================
		steptime = GetTimer();
		time += steptime;
		if(c%n_stats!=0)
			printIterTime(c,steptime);
	}

//================================================================================================
// End of time stepping loop - save final results and clean up workspace variables
//================================================================================================
	printf("Total time elapsed: %2.2fs\n", time/1000);

	// Synchronize devices
	cudaSetDevice(0);
	cudaDeviceSynchronize();

	// Copy turbulent results from GPU to CPU memory
	// Make sure that the stats counter is equal to the number of data points being saved
	if(stats_count != nt/n_stats+1)
		printf("Error: Length of stats not equal to counter!!\n");

	// Post-Simulation cleanup
	// Deallocate resources
	deallocate_memory();

	// Reset all GPUs
	for(n = 0; n<nGPUs; ++n){
		cudaSetDevice(n);
		cudaDeviceReset();
	}
	
	cudaProfilerStop();

	return 0;
}
