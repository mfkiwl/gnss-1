#include <stdlib.h>
#include <stdio.h>
#include <complex.h>
#include <helper_functions.h>
#include <helper_cuda.h>
#include <cufft.h>
#include <cuComplex.h>

#include "dnsparams.h"
#include "iofuncs.h"
#include "fftfuncs.h"

void displayDeviceProps(int numGPUs){
	int i, driverVersion = 0, runtimeVersion = 0;

	for( i = 0; i<numGPUs; ++i)
	{
		cudaSetDevice(i);

		cudaDeviceProp deviceProp;
		cudaGetDeviceProperties(&deviceProp, i);
		printf("  Device name: %s\n", deviceProp.name);

		cudaDriverGetVersion(&driverVersion);
		cudaRuntimeGetVersion(&runtimeVersion);
		printf("  CUDA Driver Version / Runtime Version          %d.%d / %d.%d\n", driverVersion/1000, (driverVersion%100)/10, runtimeVersion/1000, (runtimeVersion%100)/10);
		printf("  CUDA Capability Major/Minor version number:    %d.%d\n", deviceProp.major, deviceProp.minor);
	
		char msg[256];
		SPRINTF(msg, "  Total amount of global memory:                 %.0f MBytes \n",
				(float)deviceProp.totalGlobalMem/1048576.0f);
		printf("%s", msg);

		printf("  (%2d) Multiprocessors, (%3d) CUDA Cores/MP:     %d CUDA Cores\n",
			   deviceProp.multiProcessorCount,
			   _ConvertSMVer2Cores(deviceProp.major, deviceProp.minor),
			   _ConvertSMVer2Cores(deviceProp.major, deviceProp.minor) * deviceProp.multiProcessorCount);

		printf("\n");
	}

	return;
}

void writeDouble(double v, FILE *f)  {
	fwrite((void*)(&v), sizeof(v), 1, f);

	return;
}

void writeStats(const int c, const char* name, double in) {
	char title[0x100];
	FILE *out;
	
	snprintf(title, sizeof(title), StatsLocation, name);
	printf("Writing data to %s \n", title);
	if(c==0){ // First timestep, create new file
	  out = fopen(title, "wb");
	}
	else{ // append current timestep data to statistics file
	  out = fopen(title, "ab");
	}
	
	writeDouble(in, out);
		
	fclose(out);
}

void write2Dfields_mgpu( gpuinfo gpu, const int iter, const char var, double **in ) 
{
	int i, j, k, n, idx;
	char title[0x100];
	// snprintf(title, sizeof(title), SaveLocation, NX, Re, var, iter);
	snprintf(title, sizeof(title), SaveLocation, var, iter);
	printf("Saving data to %s \n", title);
	FILE *out = fopen(title, "wb");
	writeDouble(sizeof(double) * NX*NY*NZ, out);
	// writelu(sizeof(double) * NX*NY*NZ, out);
	for (n = 0; n < gpu.nGPUs; ++n){
		for (i = 0; i < gpu.nx[n]; ++i){
			for (j = 0; j < NY; ++j){
				for (k = 0; k < NZ; ++k){
					idx = k + 2*NZ2*j + 2*NZ2*NY*i;		// Using padded index for in-place FFT
					writeDouble(in[n][idx], out);
				}
			}
		}			
	}


	fclose(out);

	return;
}

void write3Dfields_mgpu(gpuinfo gpu, const int iter, const char var, double **in ) 
{
	int i, j, k, n, idx;
	char title[0x100];
	// snprintf(title, sizeof(title), SaveLocation, NX, Re, var, iter);
	snprintf(title, sizeof(title), SaveLocation, var, iter);
	printf("Saving data to %s \n", title);
	FILE *out = fopen(title, "wb");
	writeDouble(sizeof(double) * NX*NY*NZ, out);
	// writelu(sizeof(double) * NX*NY*NZ, out);
	k=0;
	for (n = 0; n < gpu.nGPUs; ++n){
		for (i = 0; i < gpu.nx[n]; ++i){
			for (j = 0; j < NY; ++j){
				// for (k = 0; k < NZ; ++k){
					idx = k + 2*NZ2*j + 2*NZ2*NY*i;		// Using padded index for in-place FFT
					fwrite((void *)&in[n][idx], sizeof(double), NZ, out);  // Write each k vector at once
					//writeDouble(in[n][idx], out);
				//}
			}
		}			
	}


	fclose(out);

	return;
}

void save3Dfields(int c, fftinfo fft, gpuinfo gpu, fielddata h_vel, fielddata vel){
	int n;

	if(c==0){
		printf("Saving initial data...\n");
		for(n=0; n<gpu.nGPUs; ++n){
			cudaSetDevice(n);
			cudaDeviceSynchronize();
			checkCudaErrors( cudaMemcpyAsync(h_vel.u[n], vel.u[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
			checkCudaErrors( cudaMemcpyAsync(h_vel.v[n], vel.v[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
			checkCudaErrors( cudaMemcpyAsync(h_vel.w[n], vel.w[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
			checkCudaErrors( cudaMemcpyAsync(h_vel.s[n], vel.s[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
		}

		// Write data to file
	  write3Dfields_mgpu(gpu, 0, 'u', h_vel.u);
		write3Dfields_mgpu(gpu, 0, 'v', h_vel.v);
		write3Dfields_mgpu(gpu, 0, 'w', h_vel.w);
		write3Dfields_mgpu(gpu, 0, 'z', h_vel.s);		

		return;
	}

	else{
		// Inverse Fourier Transform the velocity back to physical space for saving to file.
		inverseTransform(fft, gpu, vel.uh);
		inverseTransform(fft, gpu, vel.vh);
		inverseTransform(fft, gpu, vel.wh);
		inverseTransform(fft, gpu, vel.sh);

		// Copy data to host   
		printf( "Timestep %i Complete. . .\n", c );
		for(n=0; n<gpu.nGPUs; ++n){
			cudaSetDevice(n);
			cudaDeviceSynchronize();
			checkCudaErrors( cudaMemcpyAsync(h_vel.u[n], vel.u[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
			checkCudaErrors( cudaMemcpyAsync(h_vel.v[n], vel.v[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
			checkCudaErrors( cudaMemcpyAsync(h_vel.w[n], vel.w[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
			checkCudaErrors( cudaMemcpyAsync(h_vel.s[n], vel.s[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
		}

		// Write data to file
	  write3Dfields_mgpu(gpu, c, 'u', h_vel.u);
		write3Dfields_mgpu(gpu, c, 'v', h_vel.v);
		write3Dfields_mgpu(gpu, c, 'w', h_vel.w);
		write3Dfields_mgpu(gpu, c, 'z', h_vel.s);

		// Transform fields back to fourier space for timestepping
		forwardTransform(fft, gpu, vel.u);
		forwardTransform(fft, gpu, vel.v);
		forwardTransform(fft, gpu, vel.w);
		forwardTransform(fft, gpu, vel.s);

	return;
	}

}

void save2Dfield(int c, fftinfo fft, gpuinfo gpu, cufftDoubleComplex **fhat, double **h_f){
	int n;
		// Inverse Fourier Transform the velocity back to physical space for saving to file.
		inverseTransform(fft, gpu, fhat);

		// Copy data to host   
		printf( "Timestep %i Complete. . .\n", c );
		for(n=0; n<gpu.nGPUs; ++n){
			cudaSetDevice(n);
			cudaDeviceSynchronize();
			checkCudaErrors( cudaMemcpyAsync(h_f[n], (cufftDoubleReal**) fhat[n], sizeof(complex double)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
		}

		// Write data to file
		// write2Dfields_mgpu(gpus, c, 'zslice', h_f);

		// Transform fields back to fourier space for timestepping
		forwardTransform(fft, gpu, (cufftDoubleReal**) fhat);

	return;
}

int readDataSize(FILE *f){
	int bin;

	int flag = fread((void*)(&bin), sizeof(float), 1, f);

	if(flag == 1)
		return bin;
	else{
		return 0;
	}
}

double readDouble(FILE *f){
	double v;

	int flag = fread((void*)(&v), sizeof(double), 1, f);

	if(flag == 1)
		return v;
	else{
		return 0;
	}
}

void loadData(gpuinfo gpu, const char *name, double **var)
{ // Function to read in velocity data into multiple GPUs

	int i, j, k, n, idx, N;
	char title[0x100];
	snprintf(title, sizeof(title), DataLocation, name);
	printf("Importing data from %s \n", title);
	FILE *file = fopen(title, "rb");
	N = readDouble(file)/sizeof(double);
	if(N!=NX*NY*NZ) {
		printf("Error! N!=NX*NY*NZ");
		return;
	}
	printf("Reading data from ");
  for (n = 0; n < gpu.nGPUs; ++n){
  	printf("GPU %d",n);
    for (i = 0; i < gpu.nx[n]; ++i){
      for (j = 0; j < NY; ++j){
        for (k = 0; k < NZ; ++k){
          idx = k + 2*NZ2*j + 2*NZ2*NY*i;	
          var[n][idx] = readDouble(file);
        }
			}
		}
    printf(" ... Done!\n");
  }

	fclose(file);

	return;
}

void importVelocity(gpuinfo gpu, fielddata h_vel, fielddata vel)
{	// Import data from file
	int n;

	loadData(gpu, "u", h_vel.u);
	loadData(gpu, "v", h_vel.v);
	loadData(gpu, "w", h_vel.w);

	// Copy data from host to device
	// printf("Copy results to GPU memory...\n");
	for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);
		cudaDeviceSynchronize();
		checkCudaErrors( cudaMemcpyAsync(vel.u[n], h_vel.u[n], sizeof(cufftDoubleComplex)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
		checkCudaErrors( cudaMemcpyAsync(vel.v[n], h_vel.v[n], sizeof(cufftDoubleComplex)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
		checkCudaErrors( cudaMemcpyAsync(vel.w[n], h_vel.w[n], sizeof(cufftDoubleComplex)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
	}

	return;
}

void importScalar(gpuinfo gpu, fielddata h_vel, fielddata vel)
{	// Import data from file
	int n;

	loadData(gpu, "z", h_vel.s);

	// Copy data from host to device
	// printf("Copy results to GPU memory...\n");
	for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);
		cudaDeviceSynchronize();
		checkCudaErrors( cudaMemcpyAsync(vel.s[n], h_vel.s[n], sizeof(cufftDoubleComplex)*gpu.nx[n]*NY*NZ2, cudaMemcpyDefault) );
	}

	return;
}

void importData(gpuinfo gpu, fielddata h_vel, fielddata vel)
{	// Import data

	importVelocity(gpu, h_vel, vel);

	importScalar(gpu, h_vel, vel);

	return;
}

void printTurbStats(int c, double steptime, statistics stats)
{

	if(c==0)
		printf("\n Entering time-stepping loop...\n");
	// if(c%20==0)			// Print new header every few timesteps
		printf(" iter |   u'  |   k   |  eps  |   l   |  eta  | lambda | chi  | Area | time \n"
			"-----------------------------------------------------------\n");
	// Print statistics to screen
	printf(" %d  | %2.3f | %2.3f | %2.3f | %2.3f | %2.3f | %2.3f | %2.3f | % 2.3f | %2.3f  \n",
			c*n_stats, stats.Vrms, stats.KE, stats.epsilon, stats.l, stats.eta, stats.lambda, stats.chi, stats.area_scalar, steptime/1000);

	return;
}

void printIterTime(int c, double steptime)
{
	// Print iteration time to screen
	printf(" %d  |       |       |       |       |       |       |       |       |% 2.3f \n",
			c,steptime/1000);

	return;
}

void saveStatsData(const int c, statistics stats){

	// Save statistics data
	printf("Saving results to file...\n");
	writeStats(c, "Vrms",    stats.Vrms);
	writeStats(c, "epsilon", stats.epsilon);
	writeStats(c, "eta",     stats.eta);
	writeStats(c, "KE",      stats.KE);
	writeStats(c, "lambda",  stats.lambda);
	writeStats(c, "l",       stats.l);
	writeStats(c, "chi",     stats.chi);
	writeStats(c, "area_z",  stats.area_scalar);

	return;
}
