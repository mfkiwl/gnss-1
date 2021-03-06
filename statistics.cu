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

// include parameters for DNS
#include "dnsparams.h"
#include "statistics.h"
#include "cudafuncs.h"
#include "fftfuncs.h"
#include "iofuncs.h"
#include "solver.h"

/*
__global__
void surfaceIntegral_kernel(double *F, int w, int h, int d, double ref, double *Q, double *surfInt_Q) {
	extern __shared__ double s_F[];

	double dFdx, dFdy, dFdz, dchidx, dchidy, dchidz;

	// global indices
	const int i = blockIdx.x * blockDim.x + threadIdx.x; // column
	const int j = blockIdx.y * blockDim.y + threadIdx.y; // row
	const int k = blockIdx.z * blockDim.z + threadIdx.z; // stack
	if ((i >= w) || (j >= h) || (k >= d)) return;
	const int idx = flatten(i, j, k, w, h, d);
	// local width and height
	const int s_w = blockDim.x + 2 * RAD;
	const int s_h = blockDim.y + 2 * RAD;
	const int s_d = blockDim.z + 2 * RAD;
	// local indices
	const int s_i = threadIdx.x + RAD;
	const int s_j = threadIdx.y + RAD;
	const int s_k = threadIdx.z + RAD;
	const int s_idx = flatten(s_i, s_j, s_k, s_w, s_h, s_d);

	// Creating arrays in shared memory
	// Regular cells
	s_F[s_idx] = F[idx];

	//Halo Cells
	if (threadIdx.x < RAD) {
		s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] =
			F[flatten(i - RAD, j, k, w, h, d)];
		s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] =
			F[flatten(i + blockDim.x, j, k, w, h, d)];
	}
	if (threadIdx.y < RAD) {
		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] =
			F[flatten(i, j - RAD, k, w, h, d)];
		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] =
			F[flatten(i, j + blockDim.y, k, w, h, d)];
	}
	if (threadIdx.z < RAD) {
		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] =
			F[flatten(i, j, k - RAD, w, h, d)];
		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] =
			F[flatten(i, j, k + blockDim.z, w, h, d)];
	}

	__syncthreads();

	// Boundary Conditions
	// Making problem boundaries periodic
	if (i == 0){
		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] = 
			F[flatten(w, j, k, w, h, d)];
	}
	if (i == w - 1){
		s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] =
			F[flatten(0, j, k, w, h, d)];
	}

	if (j == 0){
		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] = 
			F[flatten(i, h, k, w, h, d)];
	}
	if (j == h - 1){
		s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] =
			F[flatten(i, 0, k, w, h, d)];
	}

	if (k == 0){
		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] = 
			F[flatten(i, j, d, w, h, d)];
	}
	if (k == d - 1){
		s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] =
			F[flatten(i, j, 0, w, h, d)];
	}

	__syncthreads();

	// Calculating dFdx and dFdy
	// Take derivatives

	dFdx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*dx);

	dFdy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*dx);

	dFdz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*dx);

	__syncthreads();

	// Test to see if z is <= Zst, which sets the value of chi
	s_F[s_idx] = (s_F[s_idx] <= ref); 

	// Test Halo Cells to form chi
	if (threadIdx.x < RAD) {
		s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] <= ref);
		s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] <= ref);
	}
	if (threadIdx.y < RAD) {
		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] <= ref);
		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] <= ref);
	}
	if (threadIdx.z < RAD) {
		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] <= ref);
		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] <= ref);
	}

	__syncthreads();

	// Take derivatives
	dchidx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*dx);

	dchidy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*dx);
	
	dchidz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*dx);

	__syncthreads();

	// Compute Length contribution for each thread
	if (dFdx == 0 && dFdy == 0 && dFdz == 0){
		s_F[s_idx] = 0.0;
	}
	else if (dchidx == 0 && dchidy == 0 && dchidz == 0){
		s_F[s_idx] = 0.0;
	}
	else{
		s_F[s_idx] = -Q[idx]*(dFdx * dchidx + dFdy * dchidy + dFdz * dchidz) / sqrtf(dFdx * dFdx + dFdy * dFdy + dFdz * dFdz);
	}

	// __syncthreads();

	// Add length contribution from each thread into block memory
	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){
		double local_Q = 0.0;
		for (int q = 1; q <= blockDim.x; ++q) {
			for (int r = 1; r <= blockDim.y; ++r){
				for (int s = 1; s <= blockDim.z; ++s){
					int local_idx = flatten(q, r, s, s_w, s_h, s_d);
					local_Q += s_F[local_idx];
				}
			}
		}
		__syncthreads();
		atomicAdd(surfInt_Q, local_Q*dx*dx*dx);
	}

	return;
}
*/
/*
__global__
void multIk(cufftDoubleComplex *f, cufftDoubleComplex *fIk, double *waveNum, const int dir)
{	// Function to multiply the function fhat by i*k
	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ2)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ2);

	// i*k*(a + bi) = -k*b + i*k*a
	
// Create temporary variables to store real and complex parts
	double a = f[idx].x;
	double b = f[idx].y;

	if(dir == 1){ // Takes derivative in 1 direction (usually x)
		fIk[idx].x = -waveNum[i]*b/((double)NN);
		fIk[idx].y = waveNum[i]*a/((double)NN);
	}
	if(dir == 2){	// Takes derivative in 2 direction (usually y)
		fIk[idx].x = -waveNum[j]*b/((double)NN);
		fIk[idx].y = waveNum[j]*a/((double)NN);
	}
	if(dir == 3){
		fIk[idx].x = -waveNum[k]*b/((double)NN);
		fIk[idx].y = waveNum[k]*a/((double)NN);
	}

	return;
}


// __global__
// void multIk_inplace(cufftDoubleComplex *f, double *waveNum, const int dir)
// {	// Function to multiply the function fhat by i*k
// 	const int i = blockIdx.x * blockDim.x + threadIdx.x;
// 	const int j = blockIdx.y * blockDim.y + threadIdx.y;
// 	const int k = blockIdx.z * blockDim.z + threadIdx.z;
// 	if ((i >= NX) || (j >= NY) || (k >= NZ2)) return;
// 	const int idx = flatten(i, j, k, NX, NY, NZ2);

// 	// i*k*(a + bi) = -k*b + i*k*a
	
// // Create temporary variables to store real and complex parts
// 	double a = f[idx].x;
// 	double b = f[idx].y;

// 	if(dir == 1){ // Takes derivative in 1 direction (usually x)
// 		f[idx].x = -waveNum[i]*b/((double)NN);
// 		f[idx].y = waveNum[i]*a/((double)NN);
// 	}
// 	if(dir == 2){	// Takes derivative in 2 direction (usually y)
// 		f[idx].x = -waveNum[j]*b/((double)NN);
// 		f[idx].y = waveNum[j]*a/((double)NN);
// 	}
// 	if(dir == 3){
// 		f[idx].x = -waveNum[k]*b/((double)NN);
// 		f[idx].y = waveNum[k]*a/((double)NN);
// 	}

// 	return;
// }

__global__
void multIk2(cufftDoubleComplex *f, cufftDoubleComplex *fIk2, double *waveNum, const int dir)
{	// Function to multiply the function fhat by i*k
	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ2)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ2);

	// i*k*(a + bi) = -k*b + i*k*a

	if(dir == 1){ // Takes derivative in 1 direction (usually x)
		fIk2[idx].x = -waveNum[i]*waveNum[i]*f[idx].x/((double)NN);
		fIk2[idx].y = -waveNum[i]*waveNum[i]*f[idx].y/((double)NN);
	}
	if(dir == 2){	// Takes derivative in 2 direction (usually y)
		fIk2[idx].x = -waveNum[j]*waveNum[j]*f[idx].x/((double)NN);
		fIk2[idx].y = -waveNum[j]*waveNum[j]*f[idx].y/((double)NN);
	}
	if(dir == 3){
		fIk2[idx].x = -waveNum[k]*waveNum[k]*f[idx].x/((double)NN);
		fIk2[idx].y = -waveNum[k]*waveNum[k]*f[idx].y/((double)NN);
	}

	return;
}


__global__
void magnitude(cufftDoubleReal *f1, cufftDoubleReal *f2, cufftDoubleReal *f3, cufftDoubleReal *mag){
	// Function to calculate the magnitude of a 3D vector field

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	// Magnitude of a 3d vector field = sqrt(f1^2 + f2^2 + f3^2)

	mag[idx] = sqrt(f1[idx]*f1[idx] + f2[idx]*f2[idx] + f3[idx]*f3[idx]);

	return;

}

__global__
void mult3AndAdd(cufftDoubleReal *f1, cufftDoubleReal *f2, cufftDoubleReal *f3, cufftDoubleReal *f4, const int flag)
{	// Function to multiply 3 functions and add (or subtract) the result to a 4th function

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	if ( flag == 1 ){
		f4[idx] = f4[idx] + f1[idx]*f2[idx]*f3[idx];
	}
	else if ( flag == 0 ){
		f4[idx] = f4[idx] - f1[idx]*f2[idx]*f3[idx];
	}
	else{
		printf("Multipy and Add function failed: please designate 1 (plus) or 0 (minus).\n");
	}
		
		return;
}

__global__
void mult2AndAdd(cufftDoubleReal *f1, cufftDoubleReal *f2, cufftDoubleReal *f3, const int flag)
{	// Function to multiply 3 functions and add (or subtract) the result to a 4th function

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	if ( flag == 1 ){
		f3[idx] = f3[idx] + f1[idx]*f2[idx];
	}
	else if ( flag == 0 ){
		f3[idx] = f3[idx] - f1[idx]*f2[idx];
	}
	else{
		printf("Multipy and Add function failed: please designate 1 (plus) or 0 (minus).\n");
	}
		
		return;
}

__global__
void multiplyOrDivide(cufftDoubleReal *f1, cufftDoubleReal *f2, cufftDoubleReal *f3, const int flag){
	// This function either multiplies two functions or divides two functions, depending on which flag is passed. The output is stored in the first array passed to the function.

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	if ( flag == 1 ){
		f3[idx] = f1[idx]*f2[idx];
	}
	else if ( flag == 0 ){
		f3[idx] = f1[idx]/f2[idx];
	}
	else{
		printf("Multipy or Divide function failed: please designate 1 (multiply) or 0 (divide).\n");
	}

	return;
}

__global__
void calcTermIV_kernel(cufftDoubleReal *gradZ, cufftDoubleReal *IV){

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	IV[idx] = 1.0/(gradZ[idx]*gradZ[idx])*IV[idx];
		
	return;

}

void calcTermIV(cufftHandle p, cufftHandle invp, double *k, cufftDoubleReal *u, cufftDoubleReal *v, cufftDoubleReal *w, cufftDoubleReal *s, double *T4){
// Function to calculate the 4th term at each grid point in the dSigmadt equation
	//  The equation for Term IV is:
	// IV = -( nx*nx*dudx + nx*ny*dudy + nx*nz*dudz + ny*nx*dvdx + ny*ny*dvdy ...
	//  		+ ny*nz*dvdz  + nz*nx*dwdx + nz*ny*dwdy + nz*nz*dwdz), 
	// where nx = -dsdx/grads, ny = -dsdy/grads, nz = -dsdz/grads,
	//  and grads = sqrt(dsdx^2 + dsdy^2 + dsdz^2).
	

	// Allocate temporary variables
	cufftDoubleReal *dsdx, *dsdy, *dsdz, *grads;
	cufftDoubleComplex *temp_c;

	// cufftResult result;

	cudaMallocManaged(&dsdx, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdy, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdz, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&grads, sizeof(cufftDoubleReal)*NN);		// Variable to hold the magnitude of gradient of s as well as other temporary variables
	cudaMallocManaged(&temp_c, sizeof(cufftDoubleComplex)*NX*NY*NZ2);

	// Set kernel variables
	const dim3 blockSize(TX, TY, TZ);
	const dim3 gridSize(divUp(NX, TX), divUp(NY, TY), divUp(NZ, TZ));

// Initialize T4 to zero
	cudaMemset(T4, 0.0, sizeof(double)*NX*NY*NZ);

// Calculate derivatives of scalar field
	// dsdx
	fftDer(p, invp, k, s, temp_c, dsdx, 1);
	// dsdy
	fftDer(p, invp, k, s, temp_c, dsdy, 2);
	// dsdz
	fftDer(p, invp, k, s, temp_c, dsdz, 3);

	// Approach: calculate each of the 9 required terms for Term IV separately and add them to the running total

// 1st term: nx*nx*dudx
	// Take derivative to get dudx
	fftDer(p, invp, k, u, temp_c, grads, 1);
	// Multiply by nx*nx and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdx, dsdx, grads, T4, 0);

// 2nd term: nx*ny*dudy
	// Take derivative to get dudy
	fftDer(p, invp, k, u, temp_c, grads, 2);
	// Multiply by nx*ny and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdx, dsdy, grads, T4, 0);

// 3rd term: nx*nz*dudz
	// Take derivative to get dudz
	fftDer(p, invp, k, u, temp_c, grads, 3);
	// Multiply by nx*nz and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdx, dsdz, grads, T4, 0);

// 4th term: ny*nx*dvdx
	// Take derivative to get dvdx
	fftDer(p, invp, k, v, temp_c, grads, 1);
	// Multiply by ny*nx and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdy, dsdx, grads, T4, 0);

// 5th term: ny*ny*dvdy
	// Take derivative to get dvdy
	fftDer(p, invp, k, v, temp_c, grads, 2);
	// Multiply by ny*ny and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdy, dsdy, grads, T4, 0);

// 6th term: ny*nz*dvdz
	// Take derivative to get dvdz
	fftDer(p, invp, k, v, temp_c, grads, 3);
	// Multiply by ny*nz and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdy, dsdz, grads, T4, 0);

// 7th term: nz*nx*dwdx
	// Take derivative to get dwdx
	fftDer(p, invp, k, w, temp_c, grads, 1);
	// Multiply by nz*nx and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdz, dsdx, grads, T4, 0);

// 8th term: nz*ny*dwdy
	// Take derivative to get dwdy
	fftDer(p, invp, k, w, temp_c, grads, 2);
	// Multiply by nz*ny and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdz, dsdy, grads, T4, 0);

// 9th term: nz*nz*dwdz
	// Take derivative to get dwdz
	fftDer(p, invp, k, w, temp_c, grads, 3);
	// Multiply by nz*nz and add to Term IV
	mult3AndAdd<<<gridSize, blockSize>>>(dsdz, dsdz, grads, T4, 0);

// Calculate grads
	magnitude<<<gridSize, blockSize>>>(dsdx, dsdy, dsdz, grads);

// Divide The sum of terms in T4 by grads^2
	calcTermIV_kernel<<<gridSize, blockSize>>>(grads, T4);

	cudaFree(dsdx);
	cudaFree(dsdy);
	cudaFree(dsdz);
	cudaFree(grads);
	cudaFree(temp_c);

	return;
}

__global__
void sum_kernel(cufftDoubleReal *f1, cufftDoubleReal *f2, cufftDoubleReal *f3, const int flag){
	// This kernel adds three functions, storing the result in the first array that was passed to it
	
	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	if ( flag == 1 ){
		f3[idx] = f1[idx] + f2[idx];
	}
	else if ( flag == 0 ){
		f3[idx] = f1[idx] - f2[idx];
	}
	else{
		printf("Sum kernel function failed: please designate 1 (add) or 0 (subtract).\n");
	}

	return;
}

__global__
void calcDiffusionVelocity_kernel(const double D, cufftDoubleReal *lapl_s, cufftDoubleReal *grads, cufftDoubleReal *diff_Vel){
// Function to calculate the diffusion velocity, given the diffusion coefficient, the laplacian of the scalar field, and the magnitude of the gradient of the scalar field
// The result of this is stored in the array holding |grads|
	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	diff_Vel[idx] = D*lapl_s[idx]/grads[idx];

	return;
}

void calcTermV(cufftHandle p, cufftHandle invp, double *waveNum, cufftDoubleReal *s, cufftDoubleReal *T5){
// Function to calculate the 5th term at each grid point in the dSigmadt equation
	//  The equation for Term V is:
	// V = -D*(dsdx2 + dsdy2 + dsdz2)/|grads| * ...
	//  		(d/dx(-nx) + d/dy(-nx) + d/dz(-nx), 
	// where nx = -dsdx/|grads|, ny = -dsdy/grads, nz = -dsdz/grads,
	//  and grads = sqrt(dsdx^2 + dsdy^2 + dsdz^2).
	

	// Allocate temporary variables
	cufftDoubleReal *dsdx, *dsdy, *dsdz;
	cufftDoubleComplex *temp_c;

	// cufftResult result;

	cudaMallocManaged(&dsdx, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdy, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdz, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&temp_c, sizeof(cufftDoubleComplex)*NX*NY*NZ2);

	// Set kernel variables
	const dim3 blockSize(TX, TY, TZ);
	const dim3 gridSize(divUp(NX, TX), divUp(NY, TY), divUp(NZ, TZ));

// Calculate derivatives of scalar field
	// dsdx
	fftDer(p, invp, waveNum, s, temp_c, dsdx, 1);
	// dsdy
	fftDer(p, invp, waveNum, s, temp_c, dsdy, 2);
	// dsdz
	fftDer(p, invp, waveNum, s, temp_c, dsdz, 3);

// Calculate grads
	magnitude<<<gridSize, blockSize>>>(dsdx, dsdy, dsdz, T5);

// Calculate normal vectors
	// Divide dsdx by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdx, T5, dsdx, 0);
	// Divide dsdy by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdy, T5, dsdy, 0);
	// Divide dsdz by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdz, T5, dsdz, 0);

// Take derivative of normal vectors 
	fftDer(p, invp, waveNum, dsdx, temp_c, dsdx, 1);
	fftDer(p, invp, waveNum, dsdy, temp_c, dsdy, 2);
	fftDer(p, invp, waveNum, dsdz, temp_c, dsdz, 3);

// Sum the derivatives of normal vectors together to form divergence(n)
	sum_kernel<<<gridSize, blockSize>>>(dsdx, dsdy, dsdx, 1);
	sum_kernel<<<gridSize, blockSize>>>(dsdx, dsdz, dsdx, 1);			// dsdx is holding the divergence of the normal vector

// Form Laplacian(s)
	// Take second derivative of scalar field in the x direction - the Laplacian will be stored in dsdy
	fft2ndDer(p, invp, waveNum, s, temp_c, dsdy, 1);		// dsdy is a placeholder variable only - don't pay attention to the name!
	
	// Take second derivative in y direction
	fft2ndDer(p, invp, waveNum, s, temp_c, dsdz, 2);		// dsdz is also a temporary placeholder
	// Add the 2nd y derivative of s to the Laplacian term (stored in dsdy)
	sum_kernel<<<gridSize, blockSize>>>(dsdy, dsdz, dsdy, 1);
	
	// Take the second derivative in the z direction
	fft2ndDer(p, invp, waveNum, s, temp_c, dsdz, 3);
	// Add the 2nd z derivative of s to the Laplacian term (stored in dsdy)
	sum_kernel<<<gridSize, blockSize>>>(dsdy, dsdz, dsdy, 1);

// Calculate the diffusion velocity
	calcDiffusionVelocity_kernel<<<gridSize, blockSize>>>(-nu/((double)Sc), dsdy, T5, T5);

// Calculate Term V
	multiplyOrDivide<<<gridSize, blockSize>>>(T5, dsdx, T5, 1);

	cudaFree(dsdx);
	cudaFree(dsdy);
	cudaFree(dsdz);
	cudaFree(temp_c);

	return;
}

__global__
void calcTermVa_kernel(const double D, cufftDoubleReal *div_n, cufftDoubleReal *Va){
// Function to calculate the diffusion velocity, given the diffusion coefficient, the laplacian of the scalar field, and the magnitude of the gradient of the scalar field
// The result of this is stored in the array holding |grads|
	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	Va[idx] = -D*div_n[idx]*div_n[idx];

	return;
}

void calcTermVa(cufftHandle p, cufftHandle invp, double *waveNum, cufftDoubleReal *s, cufftDoubleReal *T5a){
// Function to calculate the decomposition of the 5th term at each grid point in the dSigmadt equation
	//  The equation for Term Va is:
	// Va = -D*(divergence(n))^2, 
	// where n = -dsdx/|grads|,
	

	// Allocate temporary variables
	cufftDoubleReal *dsdx, *dsdy, *dsdz;
	cufftDoubleComplex *temp_c;

	// cufftResult result;

	cudaMallocManaged(&dsdx, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdy, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdz, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&temp_c, sizeof(cufftDoubleComplex)*NX*NY*NZ2);

	// Set kernel variables
	const dim3 blockSize(TX, TY, TZ);
	const dim3 gridSize(divUp(NX, TX), divUp(NY, TY), divUp(NZ, TZ));

// Calculate derivatives of scalar field
	// dsdx
	fftDer(p, invp, waveNum, s, temp_c, dsdx, 1);
	// dsdy
	fftDer(p, invp, waveNum, s, temp_c, dsdy, 2);
	// dsdz
	fftDer(p, invp, waveNum, s, temp_c, dsdz, 3);

// Calculate grads
	magnitude<<<gridSize, blockSize>>>(dsdx, dsdy, dsdz, T5a);

// Calculate normal vectors
	// Divide dsdx by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdx, T5a, dsdx, 0);
	// Divide dsdy by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdy, T5a, dsdy, 0);
	// Divide dsdz by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdz, T5a, dsdz, 0);

// Take derivative of normal vectors 
	fftDer(p, invp, waveNum, dsdx, temp_c, dsdx, 1);
	fftDer(p, invp, waveNum, dsdy, temp_c, dsdy, 2);
	fftDer(p, invp, waveNum, dsdz, temp_c, dsdz, 3);

// Zero out T5a
	cudaMemset(T5a, 0.0, sizeof(double)*NN);

// Sum the derivatives of normal vectors together to form divergence(n)
	sum_kernel<<<gridSize, blockSize>>>(T5a, dsdx, T5a, 1);
	sum_kernel<<<gridSize, blockSize>>>(T5a, dsdy, T5a, 1);
	sum_kernel<<<gridSize, blockSize>>>(T5a, dsdz, T5a, 1);			// T5a is now holding the divergence of the normal vector

// Calculate Term Va
	calcTermVa_kernel<<<gridSize, blockSize>>>(nu/((double)Sc), T5a, T5a);

	cudaFree(dsdx);
	cudaFree(dsdy);
	cudaFree(dsdz);
	cudaFree(temp_c);

	return;
}

__global__
void calcTermVb_kernel(const double D, cufftDoubleReal *Numerator, cufftDoubleReal *gradZ, cufftDoubleReal *div_n, cufftDoubleReal *Vb){

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || (j >= NY) || (k >= NZ)) return;
	const int idx = flatten(i, j, k, NX, NY, NZ);

	Vb[idx] = -D*Numerator[idx]/(gradZ[idx]*gradZ[idx])*div_n[idx];
		
	return;

}

void calcTermVb(cufftHandle p, cufftHandle invp, double *waveNum, cufftDoubleReal *s, cufftDoubleReal *T5b){
// Function to calculate the decomposition of the 5th term at each grid point in the dSigmadt equation
	//  The equation for Term Va is:
	// Va = -D*(divergence(n))^2, 
	// where n = -dsdx/|grads|,
	

	// Allocate temporary variables
	cufftDoubleReal *dsdx, *dsdy, *dsdz, *grads;
	cufftDoubleComplex *temp_c;

	// cufftResult result;

	cudaMallocManaged(&dsdx, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdy, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&dsdz, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&grads, sizeof(cufftDoubleReal)*NN);
	cudaMallocManaged(&temp_c, sizeof(cufftDoubleComplex)*NX*NY*NZ2);		// Temporary variable that is passed to the fft derivative function for intermediate calculations

	// Set kernel variables
	const dim3 blockSize(TX, TY, TZ);
	const dim3 gridSize(divUp(NX, TX), divUp(NY, TY), divUp(NZ, TZ));

///////////////////////////////////////////
	//Step 1: Calculate divergence of the normal vector
// Calculate derivatives of scalar field
	// dsdx
	fftDer(p, invp, waveNum, s, temp_c, dsdx, 1);
	// dsdy
	fftDer(p, invp, waveNum, s, temp_c, dsdy, 2);
	// dsdz
	fftDer(p, invp, waveNum, s, temp_c, dsdz, 3);

// Calculate grads
	magnitude<<<gridSize, blockSize>>>(dsdx, dsdy, dsdz, T5b);		// T5b now holds |grads|

// Calculate normal vectors
	// Divide dsdx by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdx, T5b, dsdx, 0);
	// Divide dsdy by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdy, T5b, dsdy, 0);
	// Divide dsdz by |grads|
	multiplyOrDivide<<<gridSize, blockSize>>>(dsdz, T5b, dsdz, 0);

// Take derivative of normal vectors 
	fftDer(p, invp, waveNum, dsdx, temp_c, dsdx, 1);
	fftDer(p, invp, waveNum, dsdy, temp_c, dsdy, 2);
	fftDer(p, invp, waveNum, dsdz, temp_c, dsdz, 3);

// Zero out T5a
	cudaMemset(T5b, 0.0, sizeof(double)*NN);

// Sum the derivatives of normal vectors together to form divergence(n)
	sum_kernel<<<gridSize, blockSize>>>(T5b, dsdx, T5b, 1);
	sum_kernel<<<gridSize, blockSize>>>(T5b, dsdy, T5b, 1);
	sum_kernel<<<gridSize, blockSize>>>(T5b, dsdz, T5b, 1);			// T5b is now holding the divergence of the normal vector

//////////////////////////////////////////////////////////////
	//Step 2: Calculate the numerator, grads*gradient(grads)
// Calculate |grads|
	// dsdx
	fftDer(p, invp, waveNum, s, temp_c, dsdx, 1);
	// dsdy
	fftDer(p, invp, waveNum, s, temp_c, dsdy, 2);
	// dsdz
	fftDer(p, invp, waveNum, s, temp_c, dsdz, 3);

// Calculate grads
	magnitude<<<gridSize, blockSize>>>(dsdx, dsdy, dsdz, grads);		// grads now holds |grads|

// Find the x derivative of |grads|
	fftDer(p, invp, waveNum, grads, temp_c, dsdz, 1);		// dsdz temporarily holds x derivative of |grads|
// Multiply dsdx and x derivative of |grads| and add to intermediate variable
	mult2AndAdd<<<gridSize, blockSize>>>(dsdx, dsdz, dsdx, 1);		// dsdx holds the current sum for this term

// Find the y derivative of |grads|
	fftDer(p, invp, waveNum, grads, temp_c, dsdz, 2);
// Multiply dsdy and y derivative of |grads| and add to intermediate variable
	mult2AndAdd<<<gridSize, blockSize>>>(dsdy, dsdz, dsdx, 1);

// Calculate dsdz
	fftDer(p, invp, waveNum, s, temp_c, dsdz, 3);			// Need to recalculate dsdz because the variable was used as a placeholder above
// Find the z derivative of |grads|
	fftDer(p, invp, waveNum, grads, temp_c, dsdy, 3);		// dsdy used as a placeholder for z derivative of |grads|
// Multiply dsdy and y derivative of |grads| and add to intermediate variable
	mult2AndAdd<<<gridSize, blockSize>>>(dsdy, dsdz, dsdx, 1);		// Multiplies dsdz and z derivative of |grads| and stores in dsdx variable

////////////////////////////////////////////////////////////////
	// Calculate Term Vb
	calcTermVb_kernel<<<gridSize, blockSize>>>(nu/((double)Sc), dsdx, grads, T5b, T5b);

	cudaFree(dsdx);
	cudaFree(dsdy);
	cudaFree(dsdz);
	cudaFree(grads);
	cudaFree(temp_c);

	return;
}

void calcSurfaceProps(cufftHandle p, cufftHandle invp, double *waveNum, cufftDoubleReal *u, cufftDoubleReal *v, cufftDoubleReal *w, cufftDoubleReal *z, double Zst, double *SA, double *T4, double *T5, double *T5a, double *T5b){
// Function to calculate surface quantities

	// Declare and allocate temporary variables
	double *temp;
	cudaMallocManaged(&temp, sizeof(double)*NN);

	const dim3 blockSize(TX, TY, TZ);
	const dim3 gridSize(divUp(NX, TX), divUp(NY, TY), divUp(NZ, TZ));
	const size_t smemSize = (TX + 2*RAD)*(TY + 2*RAD)*(TZ + 2*RAD)*sizeof(double);

// Calculate surface area based on Zst
	surfaceArea_kernel<<<gridSize, blockSize, smemSize>>>(z, NX, NY, NZ, Zst, SA);
	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess) 
    printf("Error: %s\n", cudaGetErrorString(err));

// Calculate Term IV
	calcTermIV(p, invp, waveNum, u, v, w, z, temp);

	// Integrate TermIV over the flame surface (Refer to Mete's thesis for more info on the surface integration technique)
	surfaceIntegral_kernel<<<gridSize, blockSize, smemSize>>>(z, NX, NY, NZ, Zst, temp, T4);
	err = cudaGetLastError();
	if (err != cudaSuccess) 
    printf("Error: %s\n", cudaGetErrorString(err));

	cudaDeviceSynchronize();

// Calculate Term V
	calcTermV(p, invp, waveNum, z, temp);

	// Integrate TermV over the flame surface (Refer to Mete's thesis for more info on the surface integration technique)
	surfaceIntegral_kernel<<<gridSize, blockSize, smemSize>>>(z, NX, NY, NZ, Zst, temp, T5);
	err = cudaGetLastError();
	if (err != cudaSuccess) 
    printf("Error: %s\n", cudaGetErrorString(err));

	cudaDeviceSynchronize();

// Calculate Term Va
	calcTermVa(p, invp, waveNum, z, temp);

	// Integrate TermV over the flame surface (Refer to Mete's thesis for more info on the surface integration technique)
	surfaceIntegral_kernel<<<gridSize, blockSize, smemSize>>>(z, NX, NY, NZ, Zst, temp, T5a);
	err = cudaGetLastError();
	if (err != cudaSuccess) 
    printf("Error: %s\n", cudaGetErrorString(err));

	cudaDeviceSynchronize();

// Calculate Term Vb
	calcTermVb(p, invp, waveNum, z, temp);

	// Integrate TermV over the flame surface (Refer to Mete's thesis for more info on the surface integration technique)
	surfaceIntegral_kernel<<<gridSize, blockSize, smemSize>>>(z, NX, NY, NZ, Zst, temp, T5b);
	err = cudaGetLastError();
	if (err != cudaSuccess) 
    printf("Error: %s\n", cudaGetErrorString(err));

	cudaDeviceSynchronize();

	//Post-processing
	T4[0] = T4[0]/SA[0];
	T5[0] = T5[0]/SA[0];
	T5a[0] = T5a[0]/SA[0];
	T5b[0] = T5b[0]/SA[0];

	cudaFree(temp);

}
*/

// __global__
// void surfaceArea_kernel(double *F, int w, int h, int d, double ref, double *SA) {
// 	extern __shared__ double s_F[];

// 	double dFdx, dFdy, dFdz, dchidx, dchidy, dchidz;

// 	// global indices
// 	const int i = blockIdx.x * blockDim.x + threadIdx.x; // column
// 	const int j = blockIdx.y * blockDim.y + threadIdx.y; // row
// 	const int k = blockIdx.z * blockDim.z + threadIdx.z; // stack
// 	if ((i >= w) || (j >= h) || (k >= d)) return;
// 	const int idx = flatten(i, j, k, w, h, d);
// 	// local width and height
// 	const int s_w = blockDim.x + 2 * RAD;
// 	const int s_h = blockDim.y + 2 * RAD;
// 	const int s_d = blockDim.z + 2 * RAD;
// 	// local indices
// 	const int s_i = threadIdx.x + RAD;
// 	const int s_j = threadIdx.y + RAD;
// 	const int s_k = threadIdx.z + RAD;
// 	const int s_idx = flatten(s_i, s_j, s_k, s_w, s_h, s_d);

// 	// Creating arrays in shared memory
// 	// Regular cells
// 	s_F[s_idx] = F[idx];

// 	//Halo Cells
// 	if (threadIdx.x < RAD) {
// 		s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i - RAD, j, k, w, h, d)];
// 		s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i + blockDim.x, j, k, w, h, d)];
// 	}
// 	if (threadIdx.y < RAD) {
// 		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i, j - RAD, k, w, h, d)];
// 		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i, j + blockDim.y, k, w, h, d)];
// 	}
// 	if (threadIdx.z < RAD) {
// 		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] =
// 			F[flatten(i, j, k - RAD, w, h, d)];
// 		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] =
// 			F[flatten(i, j, k + blockDim.z, w, h, d)];
// 	}

// 	__syncthreads();

// 	// Boundary Conditions
// 	// Making problem boundaries periodic
// 	if (i == 0){
// 		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] = 
// 			F[flatten(w, j, k, w, h, d)];
// 	}
// 	if (i == w - 1){
// 		s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] =
// 			F[flatten(0, j, k, w, h, d)];
// 	}

// 	if (j == 0){
// 		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] = 
// 			F[flatten(i, h, k, w, h, d)];
// 	}
// 	if (j == h - 1){
// 		s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i, 0, k, w, h, d)];
// 	}

// 	if (k == 0){
// 		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] = 
// 			F[flatten(i, j, d, w, h, d)];
// 	}
// 	if (k == d - 1){
// 		s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] =
// 			F[flatten(i, j, 0, w, h, d)];
// 	}

// 	// __syncthreads();

// 	// Calculating dFdx and dFdy
// 	// Take derivatives

// 	dFdx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*dx);

// 	dFdy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*dx);

// 	dFdz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*dx);

// 	__syncthreads();

// 	// Test to see if z is <= Zst, which sets the value of chi
// 	s_F[s_idx] = (s_F[s_idx] <= ref); 

// 	// Test Halo Cells to form chi
// 	if (threadIdx.x < RAD) {
// 		s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] <= ref);
// 		s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] <= ref);
// 	}
// 	if (threadIdx.y < RAD) {
// 		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] <= ref);
// 		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] <= ref);
// 	}
// 	if (threadIdx.z < RAD) {
// 		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] <= ref);
// 		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] <= ref);
// 	}

// 	__syncthreads();

// 	// Take derivatives
// 	dchidx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*dx);

// 	dchidy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*dx);
	
// 	dchidz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*dx);

// 	__syncthreads();

// 	// Compute Length contribution for each thread
// 	if (dFdx == 0 && dFdy == 0 && dFdz == 0){
// 		s_F[s_idx] = 0;
// 	}
// 	else if (dchidx == 0 && dchidy == 0 && dchidz == 0){
// 		s_F[s_idx] = 0;
// 	}
// 	else{
// 		s_F[s_idx] = -(dFdx * dchidx + dFdy * dchidy + dFdz * dchidz) / sqrtf(dFdx * dFdx + dFdy * dFdy + dFdz * dFdz);
// 	}

// 	// __syncthreads();

// 	// Add length contribution from each thread into block memory
// 	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){
// 		double local_SA = 0.0;
// 		for (int q = 1; q <= blockDim.x; ++q) {
// 			for (int r = 1; r <= blockDim.y; ++r){
// 				for (int s = 1; s <= blockDim.z; ++s){
// 					int local_idx = flatten(q, r, s, s_w, s_h, s_d);
// 					local_SA += s_F[local_idx];
// 				}
// 			}
// 		}
// 		__syncthreads();
// 		atomicAdd(SA, local_SA*dx*dx*dx);
// 	}

// 	return;
// }


// __global__
// void surfaceArea_kernel_mgpu(const int start_x, const int w, const int h, const int d, double *F, double ref, double *SA) {
// 	extern __shared__ double s_F[];

// 	double dFdx, dFdy, dFdz, dchidx, dchidy, dchidz;

// 	// global indices
// 	const int i = blockIdx.x * blockDim.x + threadIdx.x; // column
// 	const int j = blockIdx.y * blockDim.y + threadIdx.y; // row
// 	const int k = blockIdx.z * blockDim.z + threadIdx.z; // stack
// 	if (((i+start_x) >= NX) || (j >= NY) || (k >= NZ)) return;
// 	const int idx = flatten(i, j, k, w, h, d);
// 	// local width and height
// 	const int s_w = blockDim.x + 2 * RAD;
// 	const int s_h = blockDim.y + 2 * RAD;
// 	const int s_d = blockDim.z + 2 * RAD;
// 	// local indices
// 	const int s_i = threadIdx.x + RAD;
// 	const int s_j = threadIdx.y + RAD;
// 	const int s_k = threadIdx.z + RAD;
// 	const int s_idx = flatten(s_i, s_j, s_k, s_w, s_h, s_d);

// 	// Creating arrays in shared memory
// 	// Regular cells
// 	s_F[s_idx] = F[idx];

// 	//Halo Cells
// 	if (threadIdx.x < RAD) {
// 		s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i - RAD, j, k, w, h, d)];
// 		s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i + blockDim.x, j, k, w, h, d)];
// 	}
// 	if (threadIdx.y < RAD) {
// 		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i, j - RAD, k, w, h, d)];
// 		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i, j + blockDim.y, k, w, h, d)];
// 	}
// 	if (threadIdx.z < RAD) {
// 		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] =
// 			F[flatten(i, j, k - RAD, w, h, d)];
// 		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] =
// 			F[flatten(i, j, k + blockDim.z, w, h, d)];
// 	}

// 	__syncthreads();

// 	// Boundary Conditions
// 	// Making problem boundaries periodic
// 	if (i == 0){
// 		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] = 
// 			F[flatten(w, j, k, w, h, d)];
// 	}
// 	if (i == w - 1){
// 		s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] =
// 			F[flatten(0, j, k, w, h, d)];
// 	}

// 	if (j == 0){
// 		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] = 
// 			F[flatten(i, h, k, w, h, d)];
// 	}
// 	if (j == h - 1){
// 		s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] =
// 			F[flatten(i, 0, k, w, h, d)];
// 	}

// 	if (k == 0){
// 		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] = 
// 			F[flatten(i, j, d, w, h, d)];
// 	}
// 	if (k == d - 1){
// 		s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] =
// 			F[flatten(i, j, 0, w, h, d)];
// 	}

// 	// __syncthreads();

// 	// Calculating dFdx and dFdy
// 	// Take derivatives

// 	dFdx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*DX);

// 	dFdy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*DX);

// 	dFdz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*DX);

// 	__syncthreads();

// 	// Test to see if z is <= Zst, which sets the value of chi
// 	s_F[s_idx] = (s_F[s_idx] <= ref); 

// 	// Test Halo Cells to form chi
// 	if (threadIdx.x < RAD) {
// 		s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] <= ref);
// 		s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] <= ref);
// 	}
// 	if (threadIdx.y < RAD) {
// 		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] <= ref);
// 		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] <= ref);
// 	}
// 	if (threadIdx.z < RAD) {
// 		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] <= ref);
// 		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] <= ref);
// 	}

// 	__syncthreads();

// 	// Take derivatives
// 	dchidx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*DX);

// 	dchidy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*DX);
	
// 	dchidz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
// 		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*DX);

// 	__syncthreads();

// 	// Compute Length contribution for each thread
// 	if (dFdx == 0 && dFdy == 0 && dFdz == 0){
// 		s_F[s_idx] = 0;
// 	}
// 	else if (dchidx == 0 && dchidy == 0 && dchidz == 0){
// 		s_F[s_idx] = 0;
// 	}
// 	else{
// 		s_F[s_idx] = -(dFdx * dchidx + dFdy * dchidy + dFdz * dchidz) / sqrtf(dFdx * dFdx + dFdy * dFdy + dFdz * dFdz);
// 	}

// 	// __syncthreads();

// 	// Add length contribution from each thread into block memory
// 	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){
// 		double local_SA = 0.0;
// 		for (int p = RAD; p <= blockDim.x; ++p) {
// 			for (int q = RAD; q <= blockDim.y; ++q){
// 				for (int r = RAD; r <= blockDim.z; ++r){
// 					int local_idx = flatten(p, q, r, s_w, s_h, s_d);
// 					local_SA += s_F[local_idx];
// 				}
// 			}
// 		}
// 		__syncthreads();
// 		atomicAdd(SA, local_SA*DX*DX*DX);
// 	}

// 	return;
// }

void exchangeHalo_mgpu(gpudata gpu, cufftDoubleReal **f, cufftDoubleReal **left, cufftDoubleReal **right){
	// Exchange halo data
	int n, idx_s;
	size_t size;
	cudaError_t err;
	
	for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);
		size = sizeof(cufftDoubleComplex)*NZ2*NY*RAD;   // Bytes of data to copy, based on stencil radius
		idx_s = flatten((gpu.nx[n]-RAD),0,0,NX,NY,2*NZ2); // Starting index for data to send to buffer

		// Periodic boundary conditions: right boundary of f[n] goes to left[n+1]
		if(n==gpu.nGPUs-1){  // Right boundary of domain
		  checkCudaErrors( cudaMemcpy( left[0], &f[n][idx_s], size, cudaMemcpyDefault) );
		}
		else{ // Interior boundaries
		  checkCudaErrors( cudaMemcpy( left[n+1], &f[n][idx_s], size, cudaMemcpyDefault) );
		}
		// Periodic boundary conditions: left boundary of f[n] goes to right[n+1]
		if(n==0){   // Left boundary of domain
		  checkCudaErrors( cudaMemcpy( right[gpu.nGPUs-1], f[0], size, cudaMemcpyDefault) );
		}
		else{   // Interior boundaries
		  checkCudaErrors( cudaMemcpy( right[n-1], f[n], size, cudaMemcpyDefault) );
		}
	}
	
	err = cudaGetLastError();
	if (err != cudaSuccess) 
	  printf("Error: %s\n", cudaGetErrorString(err));
	
	return;
}

__global__ void volumeAverage_kernel(double nx, double *f, double *result, const int type)
{
  int idx, s_idx, k;
  extern __shared__ double tmp[];
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
  const int s_w = blockDim.x;
	const int s_h = blockDim.y;
	const int s_col = threadIdx.x;
	const int s_row = threadIdx.y;
	if ((i >= nx) || (j >= NY)) return;
	s_idx = flatten(s_col, s_row, 0, s_w, s_h, 1);
	
	// Initialize tmp
	tmp[s_idx] = 0.0;
	
	switch(type){
	  case 0: 
	    // Sum z-vectors into 2-D plane
	    for(k=0; k<NZ; ++k){
	      idx = flatten(i,j,k,nx,NY,2*NZ2);   // Using padded index for in-place FFT
	      tmp[s_idx] += f[idx]/NN;    // Simple volume average
	    } break;
	  
	  case 1: 
	    // Sum z-vectors into 2-D plane
	    for(k=0; k<NZ; ++k){
	      idx = flatten(i,j,k,nx,NY,2*NZ2);   // Using padded index for in-place FFT
	      tmp[s_idx] += f[idx]*f[idx]/NN;   // Squaring argument for RMS calculation
	    } break;
	}

	__syncthreads();
	
	// Sum each thread block and then add to result
	if (threadIdx.x == 0 && threadIdx.y == 0){

		double blockSum = 0.0;
		for (int n = 0; n < blockDim.x*blockDim.y*blockDim.z; ++n) {
			blockSum += tmp[n];
		}
		
		// Add contributions from each block
		atomicAdd(result, blockSum);
	}
  
  return;
}

double volumeAverage(gpudata gpu, double **f, statistics *stats)
{   // Function to calculate volume average of a 3-d field variable

  int n;
  double average=0.0;
  for(n=0; n<gpu.nGPUs; ++n){
    cudaSetDevice(n); 

	  // Set thread and block dimensions for kernal calls
    const dim3 blockSize(TX, TY, 1);
	  const dim3 gridSize(divUp(gpu.nx[n], TX), divUp(NY, TY), 1);
	  const size_t smemSize = TX*TY*sizeof(double);
	  // pass type=0 for simple volume average
	  volumeAverage_kernel<<<gridSize,blockSize,smemSize>>>(gpu.nx[n], f[n], &stats[n].tmp,0);
  }
  
  synchronizeGPUs(gpu.nGPUs);
  // Add results from GPUs
  for(n=0; n<gpu.nGPUs; ++n)
	  average += stats[n].tmp;
    
  return average;
}


double volumeAverage_rms(gpudata gpu, double **f, statistics *stats)
{   // Function to calculate volume average of a 3-d field variable

  int n;
  double average=0.0;
  for(n=0; n<gpu.nGPUs; ++n){
    cudaSetDevice(n); 

	  // Set thread and block dimensions for kernal calls
    const dim3 blockSize(TX, TY, 1);
	  const dim3 gridSize(divUp(gpu.nx[n], TX), divUp(NY, TY), 1);
	  const size_t smemSize = TX*TY*sizeof(double);
	  // Pass type=1 for rms calculation
	  volumeAverage_kernel<<<gridSize,blockSize,smemSize>>>(gpu.nx[n], f[n], &stats[n].tmp, 1);
  }
  
  synchronizeGPUs(gpu.nGPUs);
  // Add results from GPUs
  for(n=0; n<gpu.nGPUs; ++n)
	  average += stats[n].tmp;
    
  return sqrt(average);
}


__global__
void surfaceArea_kernel_mgpu(const int nx, const int w, const int h, const int d, double *F, double *left, double *right, double ref, double *SA) {
	extern __shared__ double s_F[];

	double dFdx, dFdy, dFdz, dchidx, dchidy, dchidz;

	// global indices
	const int i = blockIdx.x * blockDim.x + threadIdx.x; // column
	const int j = blockIdx.y * blockDim.y + threadIdx.y; // row
	const int k = blockIdx.z * blockDim.z + threadIdx.z; // stack
	if ((i >= nx) || (j >= NY) || (k >= NZ)) return;  // Use i+start_x for global domain index
	const int idx = flatten(i, j, k, nx, h, 2*(d/2+1));  // idx is the local index for each GPU (note: w is not used to calculate the index)
	// local width and height
	const int s_w = blockDim.x + 2 * RAD;
	const int s_h = blockDim.y + 2 * RAD;
	const int s_d = blockDim.z + 2 * RAD;
	// local indices
	const int s_i = threadIdx.x + RAD;
	const int s_j = threadIdx.y + RAD;
	const int s_k = threadIdx.z + RAD;
	const int s_idx = flatten(s_i, s_j, s_k, s_w, s_h, s_d);

	// Creating arrays in shared memory
	// Interior cells
	s_F[s_idx] = F[idx];
  
  // Load data into shared memory
	if (threadIdx.x < RAD) {
	  s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] =
			  F[flatten(i - RAD, j, k, w, h, 2*(d/2+1))];   // Left boundary of CUDA block
    s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] =
			  F[flatten(i + blockDim.x, j, k, w, h, 2*(d/2+1))];    // Right boundary of CUDA block
  }
	if (threadIdx.y < RAD) {
		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] =
			F[flatten(i, j - RAD, k, w, h, 2*(d/2+1))];
		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] =
			F[flatten(i, j + blockDim.y, k, w, h, 2*(d/2+1))];
	}
	if (threadIdx.z < RAD) {
		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] =
			F[flatten(i, j, k - RAD, w, h, 2*(d/2+1))];
		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] =
			F[flatten(i, j, k + blockDim.z, w, h, 2*(d/2+1))];
	}

	__syncthreads();

	// Impose Boundary Conditions
  if (i == 0){    // Left boundary
	  s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] = 
		  left[flatten(0, j, k, w, h, 2*(d/2+1))];
	}
	if (i == nx - 1){  // Right boundary
	  s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] =
		  right[flatten(0, j, k, w, h, 2*(d/2+1))];
	}
	if (j == 0){
		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] = 
			F[flatten(i, h-1, k, w, h, 2*(d/2+1))];
	}
	if (j == h - 1){
		s_F[flatten(s_i, s_j + RAD, s_k, s_w, s_h, s_d)] =
			F[flatten(i, 0, k, w, h, 2*(d/2+1))];
	}
	if (k == 0){
		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] = 
			F[flatten(i, j, d-1, w, h, 2*(d/2+1))];
	}
	if (k == d - 1){
		s_F[flatten(s_i, s_j, s_k + RAD, s_w, s_h, s_d)] =
			F[flatten(i, j, 0, w, h, 2*(d/2+1))];
	}

	__syncthreads();

	// Calculating dFdx and dFdy
	// Take derivatives

	dFdx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*DX);

	dFdy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*DX);

	dFdz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*DX);

	__syncthreads();

	// Test to see if z is <= Zst, which sets the value of chi
	s_F[s_idx] = (s_F[s_idx] <= ref); 

	// Test Halo Cells to form chi
	if (threadIdx.x < RAD) {
		s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i - RAD, s_j, s_k, s_w, s_h, s_d)] <= ref);
		s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i + blockDim.x, s_j, s_k, s_w, s_h, s_d)] <= ref);
	}
	if (threadIdx.y < RAD) {
		s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j - RAD, s_k, s_w, s_h, s_d)] <= ref);
		s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j + blockDim.y, s_k, s_w, s_h, s_d)] <= ref);
	}
	if (threadIdx.z < RAD) {
		s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k - RAD, s_w, s_h, s_d)] <= ref);
		s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] = (s_F[flatten(s_i, s_j, s_k + blockDim.z, s_w, s_h, s_d)] <= ref);
	}

	__syncthreads();

	// Take derivatives
	dchidx = ( s_F[flatten(s_i + 1, s_j, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i - 1, s_j, s_k, s_w, s_h, s_d)] ) / (2.0*DX);

	dchidy = ( s_F[flatten(s_i, s_j + 1, s_k, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j - 1, s_k, s_w, s_h, s_d)] ) / (2.0*DX);
	
	dchidz = ( s_F[flatten(s_i, s_j, s_k + 1, s_w, s_h, s_d)] - 
		s_F[flatten(s_i, s_j, s_k - 1, s_w, s_h, s_d)] ) / (2.0*DX);

	__syncthreads();

	// Compute Length contribution for each thread
	if (dFdx == 0 && dFdy == 0 && dFdz == 0){
		s_F[s_idx] = 0;
	}
	else if (dchidx == 0 && dchidy == 0 && dchidz == 0){
		s_F[s_idx] = 0;
	}
	else{
		s_F[s_idx] = -(dFdx*dchidx + dFdy*dchidy + dFdz*dchidz) / sqrtf(dFdx*dFdx + dFdy*dFdy + dFdz*dFdz);
	}

	__syncthreads();

	// Add length contribution from each thread into block memory
	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){
		double local_SA = 0.0;
		for (int p = RAD; p <= blockDim.x; ++p) {
			for (int q = RAD; q <= blockDim.y; ++q){
				for (int r = RAD; r <= blockDim.z; ++r){
					int local_idx = flatten(p, q, r, s_w, s_h, s_d);
					local_SA += s_F[local_idx];
				}
			}
		}
		__syncthreads();
		atomicAdd(SA, local_SA*DX*DX*DX);
	}

	return;
}

double calcSurfaceArea_mgpu(gpudata gpu, cufftDoubleReal **f, cufftDoubleReal **left, cufftDoubleReal **right, double iso, statistics *stats){
// Function to calculate surface quantities
  int n;
  double SA = 0.0;
	 
	// Exchange halo data for finite difference stencil
  exchangeHalo_mgpu(gpu, f, left, right);

	synchronizeGPUs(gpu.nGPUs);			// Synchronize GPUs
	
	for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);	
		// Declare and allocate temporary variables
		const dim3 blockSize(TX, TY, TZ);
		const dim3 gridSize(divUp(gpu.nx[n], TX), divUp(NY, TY), divUp(NZ, TZ));
		const size_t smemSize = (TX + 2*RAD)*(TY + 2*RAD)*(TZ + 2*RAD)*sizeof(double);

    stats[n].tmp=0.0; // Initialize temp value to zero
    
		// Calculate surface area based on the value of iso
		surfaceArea_kernel_mgpu<<<gridSize, blockSize, smemSize>>>(gpu.nx[n], NX, NY, NZ, f[n], left[n], right[n], iso, &stats[n].tmp);
	}
	
	synchronizeGPUs(gpu.nGPUs);
	// Collect results from all GPUs
	for(n=0;n<gpu.nGPUs;++n)
	  SA += stats[n].tmp;

	return SA;

}

__global__
void calcVrmsKernel_mgpu(int start_y, cufftDoubleComplex *u1hat, cufftDoubleComplex *u2hat, cufftDoubleComplex *u3hat, double *RMS, double *KE){
// Function to calculate the RMS velocity of a flow field

	// Declare variables
	extern __shared__ double vel_mag[];

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	if ((i >= NX) || ( (j+start_y) >= NY) || (k >= NZ)) return;
	int kp = NZ-k;
	const int idx = flatten(j, i, k, NY, NX, NZ2);
	const int idx2 = flatten(j, i, kp, NY, NX, NZ2);
	// Create shared memory indices
	// local width and height
	const int s_w = blockDim.x;
	const int s_h = blockDim.y;
	const int s_d = blockDim.z;
	// local indices
	const int s_col = threadIdx.x;
	const int s_row = threadIdx.y;
	const int s_sta = threadIdx.z;
	const int s_idx = flatten(s_row, s_col, s_sta, s_h, s_w, s_d);

// Step 1: Calculate velocity magnitude at each point in the domain
	// Requires calculation of uu*, or multiplication of u with its complex conjugate
	// Mathematically, multiplying a number u = a + ib by its complex conjugate means
	// uu* = (a + ib) * (a - ib) = a^2 + b^2.
	// Some funky indexing is required because only half of the domain is represented in the complex form
	// (or is it? Can potentially just compute on the standard grid and multiply by 2....)
	if (k < NZ2){
		vel_mag[s_idx] = (u1hat[idx].x*u1hat[idx].x + u1hat[idx].y*u1hat[idx].y)/((double)NN*NN) + (u2hat[idx].x*u2hat[idx].x + u2hat[idx].y*u2hat[idx].y)/((double)NN*NN) + (u3hat[idx].x*u3hat[idx].x + u3hat[idx].y*u3hat[idx].y)/((double)NN*NN);
	}
	else{
		vel_mag[s_idx] = (u1hat[idx2].x*u1hat[idx2].x + u1hat[idx2].y*u1hat[idx2].y)/((double)NN*NN) + (u2hat[idx2].x*u2hat[idx2].x + u2hat[idx2].y*u2hat[idx2].y)/((double)NN*NN) + (u3hat[idx2].x*u3hat[idx2].x + u3hat[idx2].y*u3hat[idx2].y)/((double)NN*NN);
	}

	__syncthreads();

// Step 2: Add all of the contributions together ( need to use Atomic Add to make sure that all points are added correctly)
// Need to perform data reduction
	// Calculate sum of the velocity magnitude for each block
	if (s_idx == 0){

		double blockSum = 0.0;
		int c;
		for (c = 0; c < blockDim.x*blockDim.y*blockDim.z; ++c) {
			blockSum += vel_mag[c];
		}

		__syncthreads();

		// Step 3: Add all blocks together into device memory using Atomic operations (requires -arch=sm_60 or higher)

		// Kinetic Energy
		atomicAdd(KE, blockSum/2.0);
		// RMS velocity
		atomicAdd(RMS, blockSum/3.0);

	}

	return;
}

void calcVrms(gpudata gpu, griddata grid, fielddata vel, statistics *stats)
{ 
  int n;
  for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);

		// Set thread and block dimensions for kernal calls
		const dim3 blockSize(TX, TY, TZ);
		const dim3 gridSize(divUp(NX, TX), divUp(gpu.ny[n], TY), divUp(NZ, TZ));
		const size_t smemSize = TX*TY*TZ*sizeof(double);
		
		calcVrmsKernel_mgpu<<<gridSize, blockSize, smemSize>>>(gpu.start_y[n], vel.uh[n], vel.vh[n], vel.wh[n], &stats[n].Vrms, &stats[n].KE);

  }
  
  synchronizeGPUs(gpu.nGPUs);
  // Sum contributions from all GPUs
  for(n=1; n<gpu.nGPUs; ++n){
    stats[0].Vrms += stats[n].Vrms;
    stats[0].KE += stats[n].KE;
  }
  
  //calcVrms kernel doesn't actually calculate the RMS velocity - Take square root to get Vrms
	stats[0].Vrms = sqrt(stats[0].Vrms);
  
  return;
}

__global__
void calcEpsilonKernel_mgpu(int start_y, double *k1, double *k2, double *k3, cufftDoubleComplex *u1hat, cufftDoubleComplex *u2hat, cufftDoubleComplex *u3hat, double *eps){
// Function to calculate the rate of dissipation of kinetic energy in a flow field

	// Declare variables
	extern __shared__ double vel_mag[];

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	const int jj = j + start_y;  // Absolute index for referencing wavenumbers
	if ((i >= NX) || (jj >= NY) || (k >= NZ)) return;
	int kp = NZ-k;
	const int idx = flatten(j, i, k, NY, NX, NZ2);
	const int idx2 = flatten(j, i, kp, NY, NX, NZ2);
	// Create shared memory indices
	// local width and height
	const int s_w = blockDim.x;
	const int s_h = blockDim.y;
	const int s_d = blockDim.z;
	// local indices
	const int s_col = threadIdx.x;
	const int s_row = threadIdx.y;
	const int s_sta = threadIdx.z;
	const int s_idx = flatten(s_row, s_col, s_sta, s_h, s_w, s_d);
	
	double k_sq = k1[i]*k1[i] + k2[jj]*k2[jj] + k3[k]*k3[k];

// Step 1: Calculate k_sq*velocity magnitude at each point in the domain
	// Requires calculation of uu*, or multiplication of u with its complex conjugate
	// Mathematically, multiplying a number u = a + ib by its complex conjugate means
	// uu* = (a + ib) * (a - ib) = a^2 + b^2.
	// Some funky indexing is required because only half of the domain is represented in the complex form
	if (k < NZ2){
		vel_mag[s_idx] = (k_sq)*( (u1hat[idx].x*u1hat[idx].x + u1hat[idx].y*u1hat[idx].y)/((double)NN*NN) + (u2hat[idx].x*u2hat[idx].x + u2hat[idx].y*u2hat[idx].y)/((double)NN*NN) + (u3hat[idx].x*u3hat[idx].x + u3hat[idx].y*u3hat[idx].y)/((double)NN*NN) );
	}
	else{
		vel_mag[s_idx] = (k_sq)*( (u1hat[idx2].x*u1hat[idx2].x + u1hat[idx2].y*u1hat[idx2].y)/((double)NN*NN) + (u2hat[idx2].x*u2hat[idx2].x + u2hat[idx2].y*u2hat[idx2].y)/((double)NN*NN) + (u3hat[idx2].x*u3hat[idx2].x + u3hat[idx2].y*u3hat[idx2].y)/((double)NN*NN) );
	}

	__syncthreads();

// Step 2: Add all of the contributions together ( need to use Atomic Add to make sure that all points are added correctly)
// Need to perform data reduction
// Calculate sum of the nu*k_sq*velocity magnitude for each block
	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){

		double blockSum = 0.0;
		for (int i = 0; i < blockDim.x*blockDim.y*blockDim.z; ++i) {
			blockSum += nu*vel_mag[i];
		}
		__syncthreads();

		// Dissipation Rate
		atomicAdd(eps, blockSum);
	}

	return;
}

void calcDissipationRate(gpudata gpu, griddata grid, fielddata vel, statistics *stats)
{ 
  int n;
  for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);

		// Set thread and block dimensions for kernal calls
		const dim3 blockSize(TX, TY, TZ);
		const dim3 gridSize(divUp(NX, TX), divUp(gpu.ny[n], TY), divUp(NZ, TZ));
		const size_t smemSize = TX*TY*TZ*sizeof(double);
		
		calcEpsilonKernel_mgpu<<<gridSize, blockSize, smemSize>>>(gpu.start_y[n], grid.kx[n], grid.ky[n], grid.kz[n], vel.uh[n], vel.vh[n], vel.wh[n], &stats[n].epsilon);

  }
  
  synchronizeGPUs(gpu.nGPUs);
  // Sum contributions from all GPUs
  for(n=1; n<gpu.nGPUs; ++n)
    stats[0].epsilon += stats[n].epsilon;
  

  return;
}

__global__
void calcIntegralLengthKernel_mgpu(int start_y, double *k1, double *k2, double *k3, cufftDoubleComplex *u1hat, cufftDoubleComplex *u2hat, cufftDoubleComplex *u3hat, double *l){
// Function to calculate the integral length scale of a turbulent flow field

	// Declare variables
	extern __shared__ double vel_mag[];

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	const int jj = j + start_y;  // Absolute index for referencing wavenumbers
	if ((i >= NX) || (jj >= NY) || (k >= NZ)) return;
	int kp = NZ-k;
	const int idx = flatten(j, i, k, NY, NX, NZ2);
	const int idx2 = flatten(j, i, kp, NY, NX, NZ2);
	// Create shared memory indices
	// local width and height
	const int s_w = blockDim.x;
	const int s_h = blockDim.y;
	const int s_d = blockDim.z;
	// local indices
	const int s_col = threadIdx.x;
	const int s_row = threadIdx.y;
	const int s_sta = threadIdx.z;
	const int s_idx = flatten(s_row, s_col, s_sta, s_h, s_w, s_d);
	
	double k_sq = k1[i]*k1[i] + k2[jj]*k2[jj] + k3[k]*k3[k];

// Step 1: Calculate velocity magnitude at each point in the domain
	// Requires calculation of uu*, or multiplication of u with its complex conjugate
	// Mathematically, multiplying a number u = a + ib by its complex conjugate means
	// uu* = (a + ib) * (a - ib) = a^2 + b^2.
	// Some funky indexing is required because only half of the domain is represented in the complex form
	vel_mag[s_idx] = 0.0;
	if (k_sq > 0){
		if (k < NZ2){
			vel_mag[s_idx] = ( (u1hat[idx].x*u1hat[idx].x + u1hat[idx].y*u1hat[idx].y)/((double)NN*NN) + (u2hat[idx].x*u2hat[idx].x + u2hat[idx].y*u2hat[idx].y)/((double)NN*NN) + (u3hat[idx].x*u3hat[idx].x + u3hat[idx].y*u3hat[idx].y)/((double)NN*NN) )/( 2.0*sqrt(k_sq) );
		}
		else{
			vel_mag[s_idx] = ( (u1hat[idx2].x*u1hat[idx2].x + u1hat[idx2].y*u1hat[idx2].y)/((double)NN*NN) + (u2hat[idx2].x*u2hat[idx2].x + u2hat[idx2].y*u2hat[idx2].y)/((double)NN*NN) + (u3hat[idx2].x*u3hat[idx2].x + u3hat[idx2].y*u3hat[idx2].y)/((double)NN*NN) )/( 2.0*sqrt(k_sq) );
		}
	}

	__syncthreads();

// Step 2: Add all of the contributions together ( need to use Atomic Add to make sure that all points are added correctly)
// Need to perform data reduction
// Calculate sum of the velocity magnitude for each block
	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){

		double blockSum = 0.0;
		for (int i = 0; i < blockDim.x*blockDim.y*blockDim.z; ++i) {
			blockSum += vel_mag[i];
		}

		__syncthreads();

		// Dissipation Rate
		atomicAdd(l, blockSum);
	}

	return;
}

void calcIntegralLength(gpudata gpu, griddata grid, fielddata vel, statistics *stats)
{ 
  int n;
  for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);

		// Set thread and block dimensions for kernal calls
		const dim3 blockSize(TX, TY, TZ);
		const dim3 gridSize(divUp(NX, TX), divUp(gpu.ny[n], TY), divUp(NZ, TZ));
		const size_t smemSize = TX*TY*TZ*sizeof(double);
		
		calcIntegralLengthKernel_mgpu<<<gridSize, blockSize, smemSize>>>(gpu.start_y[n], grid.kx[n], grid.ky[n], grid.kz[n], vel.uh[n], vel.vh[n], vel.wh[n], &stats[n].l);

  }
  
  synchronizeGPUs(gpu.nGPUs);
  // Sum contributions from all GPUs
  for(n=1; n<gpu.nGPUs; ++n)
    stats[0].l += stats[n].l;
  
  return;
}

__global__
void calcScalarDissipationKernel_mgpu(int start_y, double *k1, double *k2, double *k3, cufftDoubleComplex *zhat, double *chi){
// Function to calculate the RMS velocity of a flow field

	// Declare variables
	extern __shared__ double sca_mag[];

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	const int jj = j + start_y;  // Absolute index for referencing wavenumbers
	if ((i >= NX) || (jj >= NY) || (k >= NZ)) return;
	int kp = NZ-k;
	const int idx = flatten(j, i, k, NY, NX, NZ2);
	const int idx2 = flatten(j, i, kp, NY, NX, NZ2);
	// Create shared memory indices
	// local width and height
	const int s_w = blockDim.x;
	const int s_h = blockDim.y;
	const int s_d = blockDim.z;
	// local indices
	const int s_col = threadIdx.x;
	const int s_row = threadIdx.y;
	const int s_sta = threadIdx.z;
	const int s_idx = flatten(s_row, s_col, s_sta, s_h, s_w, s_d);
	
	double k_sq = k1[i]*k1[i] + k2[jj]*k2[jj] + k3[k]*k3[k];

// Step 1: Calculate velocity magnitude at each point in the domain
	// Requires calculation of uu*, or multiplication of u with its complex conjugate
	// Mathematically, multiplying a number u = a + ib by its complex conjugate means
	// uu* = (a + ib) * (a - ib) = a^2 + b^2.
	// Some funky indexing is required because only half of the domain is represented in the complex form
	// (or is it? Can potentially just compute on the standard grid and multiply by 2....)
	if (k < NZ2){
		sca_mag[s_idx] = (k_sq)*(zhat[idx].x*zhat[idx].x + zhat[idx].y*zhat[idx].y)/((double)NN*NN);
	}
	else{
		sca_mag[s_idx] = (k_sq)*(zhat[idx2].x*zhat[idx2].x + zhat[idx2].y*zhat[idx2].y)/((double)NN*NN);
	}

	__syncthreads();

// Step 2: Add all of the contributions together ( need to use Atomic Add to make sure that all points are added correctly)
// Need to perform data reduction
	// Calculate sum of the velocity magnitude for each block
	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){

		double blockSum = 0.0;

		for (int i = 0; i < blockDim.x*blockDim.y*blockDim.z; ++i) {
			blockSum += 2*(nu/Sc)*sca_mag[i];
		}

		__syncthreads();

		// Step 3: Add all blocks together into device memory using Atomic operations (requires -arch=sm_60 or higher)

		// Scalar Dissipation
		atomicAdd(chi, blockSum);

	}

	return;
}

void calcScalarDissipationRate(gpudata gpu, griddata grid, fielddata vel, statistics *stats)
{ 
  int n;
  for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);

		// Set thread and block dimensions for kernal calls
		const dim3 blockSize(TX, TY, TZ);
		const dim3 gridSize(divUp(NX, TX), divUp(gpu.ny[n], TY), divUp(NZ, TZ));
		const size_t smemSize = TX*TY*TZ*sizeof(double);
		
		calcScalarDissipationKernel_mgpu<<<gridSize, blockSize, smemSize>>>(gpu.start_y[n], grid.kx[n], grid.ky[n], grid.kz[n], vel.sh[n], &stats[n].chi);

  }
  
  synchronizeGPUs(gpu.nGPUs);
  // Sum contributions from all GPUs
  for(n=1; n<gpu.nGPUs; ++n)
    stats[0].chi += stats[n].chi;
  
  return;
}

__global__
void calcEnergySpectraKernel_mgpu(int start_y, double *k1, double *k2, double *k3, cufftDoubleComplex *u1hat, cufftDoubleComplex *u2hat, cufftDoubleComplex *u3hat, double *e){
// Function to calculate the integral length scale of a turbulent flow field

	// Declare variables
	extern __shared__ double vel_mag[];

	const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
	const int k = blockIdx.z * blockDim.z + threadIdx.z;
	const int jj = j + start_y;  // Absolute index for referencing wavenumbers
	if ((i >= NX) || (jj >= NY) || (k >= NZ)) return;
	int kp = NZ-k;
	const int idx = flatten(j, i, k, NY, NX, NZ2);
	const int idx2 = flatten(j, i, kp, NY, NX, NZ2);
	// Create shared memory indices
	// local width and height
	const int s_w = blockDim.x;
	const int s_h = blockDim.y;
	const int s_d = blockDim.z;
	// local indices
	const int s_col = threadIdx.x;
	const int s_row = threadIdx.y;
	const int s_sta = threadIdx.z;
	const int s_idx = flatten(s_row, s_col, s_sta, s_h, s_w, s_d);
	
	double k_sq = k1[i]*k1[i] + k2[jj]*k2[jj] + k3[k]*k3[k];

// Step 1: Calculate velocity magnitude at each point in the domain
	// Requires calculation of uu*, or multiplication of u with its complex conjugate
	// Mathematically, multiplying a number u = a + ib by its complex conjugate means
	// uu* = (a + ib) * (a - ib) = a^2 + b^2.
	// Some funky indexing is required because only half of the domain is represented in the complex form
	vel_mag[s_idx] = 0.0;
	// if (wave[i]*wave[i] + wave[(j+start_y)]*wave[(j+start_y)] + wave[k]*wave[k] > 0){
		if (k < NZ2){
			vel_mag[s_idx] = ( (u1hat[idx].x*u1hat[idx].x + u1hat[idx].y*u1hat[idx].y)/((double)NN*NN) + (u2hat[idx].x*u2hat[idx].x + u2hat[idx].y*u2hat[idx].y)/((double)NN*NN) + (u3hat[idx].x*u3hat[idx].x + u3hat[idx].y*u3hat[idx].y)/((double)NN*NN) )/( 2.0*sqrt(k_sq) );
		}
		else{
			vel_mag[s_idx] = ( (u1hat[idx2].x*u1hat[idx2].x + u1hat[idx2].y*u1hat[idx2].y)/((double)NN*NN) + (u2hat[idx2].x*u2hat[idx2].x + u2hat[idx2].y*u2hat[idx2].y)/((double)NN*NN) + (u3hat[idx2].x*u3hat[idx2].x + u3hat[idx2].y*u3hat[idx2].y)/((double)NN*NN) )/( 2.0*sqrt(k_sq) );
		}
	// }

	__syncthreads();

// Step 2: Add all of the contributions together ( need to use Atomic Add to make sure that all points are added correctly)
// Need to perform data reduction
// Calculate sum of the velocity magnitude for each block
	if (threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0){

		double blockSum = 0.0;
		for (int i = 0; i < blockDim.x*blockDim.y*blockDim.z; ++i) {
			blockSum += vel_mag[i];
		}

		__syncthreads();

		// Dissipation Rate
		atomicAdd(e, blockSum);
	}

	return;
}


void calcSpectra_mgpu(const int c, gpudata gpu, fftdata fft, griddata grid, fielddata vel, statistics stats)
{ // Calculate sperical energy and scalar spectra
//	int n;

//	// Loop over GPUs to call kernels
//	for(n=0; n<gpu.nGPUs; ++n){
//		cudaSetDevice(n);

//		// Set thread and block dimensions for kernal calls
//		const dim3 blockSize(TX, TY, TZ);
//		const dim3 gridSize(divUp(NX, TX), divUp(gpu.ny[n], TY), divUp(NZ, TZ));
//		// const size_t smemSize = TX*TY*TZ*sizeof(double);
//		cudaError_t err;

//		// Call kernels to calculate spherical energy spectra
//		calcEnergySpectraKernel_mgpu<<<gridSize, blockSize>>>(gpu.start_y[n], grid.kx[n], vel.uh[n], vel.vh[n], vel.wh[n], &stats[n].energy_spect);
//		err = cudaGetLastError();
//		if (err != cudaSuccess) 
//	    printf("Error: %s\n", cudaGetErrorString(err));
//	}

	return;
}

__global__ void calcYprof_kernel_2D(int nx, double *data, double *prof)
{
  int idx, s_idx, k;
  double blockSum[TY] = {0.0};
  extern __shared__ double tmp[];
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
	const int j = blockIdx.y * blockDim.y + threadIdx.y;
  const int s_w = blockDim.x;
	const int s_h = blockDim.y;
	const int s_col = threadIdx.x;
	const int s_row = threadIdx.y;
	if ((i >= nx) || (j >= NY)) return;
	s_idx = flatten(s_col, s_row, 0, s_w, s_h, 1);
	
	// Initialize tmp
	tmp[s_idx] = 0.0;
	prof[j] = 0.0;
	
	// Sum z-vectors into 2-D plane
	for(k=0; k<NZ; ++k){
	  idx = flatten(i,j,k,nx,NY,2*NZ2);   // Using padded index for in-place FFT
	  tmp[s_idx] += data[idx]/(NX*NZ);
	}

	__syncthreads();
	
	// Sum each thread block and then add to result
	if (threadIdx.x == 0){

		for (int n=0; n<blockDim.x; ++n) {
		  s_idx = flatten(n, s_row, 0, s_w, s_h, 1);
			blockSum[s_row] += tmp[s_idx];
		}
		
		__syncthreads();
		
		// Add contributions from each block
		atomicAdd(&prof[j], blockSum[s_row]);
	}
  
  return;
}

void calcYprof(gpudata gpu, double **f, double **Yprof)
{ // Average over X,Z directions to create mean profiles in the Y direction

	int n,j;
	
	for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n); 

    const dim3 blockSize(TX, TY, 1);
	  const dim3 gridSize(divUp(gpu.nx[n], TX), divUp(NY, TY), 1);
	  const size_t smemSize = TX*TY*sizeof(double);
    // Calculate mean profile of u-velocity
	  calcYprof_kernel_2D<<<gridSize,blockSize,smemSize>>>(gpu.nx[n], f[n], Yprof[n]);

	}
	
	synchronizeGPUs(gpu.nGPUs);
	for(n=1;n<gpu.nGPUs;++n){
	  for(j=0;j<NY;++j){
	    Yprof[0][j] += Yprof[n][j];
	  }
	}
	
	return;
}

__global__
void VectorMagnitude_kernel(const int nx, double *f_x, double *f_y, double *f_z, double *mag_f) {

	// global indices
	const int i = blockIdx.x * blockDim.x + threadIdx.x; // column
	const int j = blockIdx.y * blockDim.y + threadIdx.y; // row
	const int k = blockIdx.z * blockDim.z + threadIdx.z; // stack
	if ((i >= nx) || (j >= NY) || (k >= NZ)) return;  // i should never exceed NX/gpu
	const int idx = flatten(i, j, k, nx, NY, 2*NZ2); // In-place fft indexing
	
	mag_f[idx] = sqrt(f_x[idx]*f_x[idx] + f_y[idx]*f_y[idx] + f_z[idx]*f_z[idx]);
	
	return;
}

void VectorMagnitude(gpudata gpu, fielddata f){
// Function to calculate vector magnitude based on x,y,z components (stored in f.u,f.v,f.w respectively)
  int n;
	 
	for(n=0; n<gpu.nGPUs; ++n){
		cudaSetDevice(n);	
		// Declare and allocate temporary variables
		const dim3 blockSize(TX, TY, TZ);
		const dim3 gridSize(divUp(gpu.nx[n], TX), divUp(NY, TY), divUp(NZ, TZ));

		// Calculate surface area based on the value of iso
		VectorMagnitude_kernel<<<gridSize, blockSize>>>(gpu.nx[n], f.u[n], f.v[n], f.w[n], f.s[n]);

	}
	
	return;

}

void calcTurbStats_mgpu(const int c, gpudata gpu, fftdata fft, griddata grid, fielddata vel, fielddata rhs, statistics *stats, profile Yprof)
{// Function to call a cuda kernel that calculates the relevant turbulent statistics

	// Synchronize GPUs before calculating statistics
	int n, nGPUs;
	//double Wiso[]={0.0001,0.002,0.005,0.001,0.002,0.005,0.01,0.02,0.05,0.1,0.2,0.5,1.0,2.0,5.0,10.0,20.0,50.0,100.0};
	//double Ziso[]={0.001,0.002,0.005,0.01,0.02,0.03,0.04,0.05,0.1,0.15,0.2,0.25,0.3,0.35,0.4,0.45,0.5,0.55,0.6};

	// Make local copy of number of GPUs (for readability)
	nGPUs = gpu.nGPUs;	

	// Initialize all statistics to 0
	for (n = 0; n<nGPUs; ++n){
	  stats[n].Vrms         = 0.0;
	  stats[n].KE           = 0.0;
	  stats[n].epsilon      = 0.0;
	  stats[n].eta          = 0.0;
	  stats[n].l            = 0.0;
	  stats[n].lambda       = 0.0;
	  stats[n].chi          = 0.0;
	  //for(i=0; i<64; ++i) {
	  //  stats[n].area_scalar[i]  = 0.0;  
	  //  stats[n].area_omega[i]   = 0.0;
	  //}
	  stats[n].energy_spect = 0.0;
	}

	synchronizeGPUs(nGPUs);
//=============================================================================================
// Calculating statistics of turbulent velocity field
//=============================================================================================
	// Statistics for turbulent velocity field
	// Launch kernels to calculate stats
	calcVrms(gpu, grid, vel, stats);
	calcDissipationRate(gpu, grid, vel, stats);
	calcIntegralLength(gpu, grid, vel, stats);
	calcScalarDissipationRate(gpu, grid, vel, stats);

	// Calculate energy and scalar spectra
	// calcSpectra_mgpu(c, gpu, fft, grid, vel, stats);
	
	// Form the vorticity in Fourier space
	vorticity(gpu, grid, vel, rhs);

	synchronizeGPUs(nGPUs);
	
//=============================================================================================
// Post-processing in physical domain
//=============================================================================================
  
  // Compute vorticity calculations first
  //==============================================

	// Transform vorticity to physical domain
	inverseTransform(fft, gpu, rhs.uh);
	inverseTransform(fft, gpu, rhs.vh);
	inverseTransform(fft, gpu, rhs.wh);
	
	synchronizeGPUs(nGPUs);
	
	// Calculate Vorticity magnitude
	VectorMagnitude(gpu, rhs);
	
	// Take volume average of vorticity magnitude
	stats[0].omega_x = volumeAverage_rms(gpu, rhs.u, stats);
	stats[0].omega_y = volumeAverage_rms(gpu, rhs.v, stats);
	stats[0].omega_z = volumeAverage_rms(gpu, rhs.w, stats);	
	stats[0].omega   = volumeAverage(gpu, rhs.s, stats);	
	
	// Calculate surface area of vorticity magnitude
 // iso = stats[0].omega;
  //stats[0].area_omega = 0.0; //calcSurfaceArea_mgpu(gpu, rhs.s, vel.left, vel.right, Wiso, stats);
	
	// Velocity statistics
	//=================================================
	// Transform primitive variables to physical domain
	inverseTransform(fft, gpu, vel.uh);
	inverseTransform(fft, gpu, vel.vh);
	inverseTransform(fft, gpu, vel.wh);
	inverseTransform(fft, gpu, vel.sh);
	inverseTransform(fft, gpu, vel.ch);
  
  // Calculate mean profiles
  calcYprof(gpu, vel.u, Yprof.u);
  calcYprof(gpu, vel.v, Yprof.v);
  calcYprof(gpu, vel.w, Yprof.w);
  calcYprof(gpu, vel.s, Yprof.s);
  calcYprof(gpu, vel.c, Yprof.c);
  
  synchronizeGPUs(nGPUs);			// Synchronize GPUs
	
  // Calculate surface area of scalar field
  // iso = 0.5;
  //stats[0].area_scalar = 0.0; //calcSurfaceArea_mgpu(gpu, vel.s, vel.left, vel.right, Ziso, stats);
  
  synchronizeGPUs(nGPUs);			// Synchronize GPUs
  
  forwardTransform(fft, gpu, vel.u);
  forwardTransform(fft, gpu, vel.v);
  forwardTransform(fft, gpu, vel.w);	
  forwardTransform(fft, gpu, vel.s);
  forwardTransform(fft, gpu, vel.c);
  
//=============================================================================================
// Collecting results from all GPUs
//=============================================================================================

	// Calculating Derived Statistics
	stats[0].lambda = sqrt( 15.0*nu*stats[0].Vrms*stats[0].Vrms/stats[0].epsilon );
	stats[0].eta = sqrt(sqrt(nu*nu*nu/stats[0].epsilon));
	stats[0].l = 3*PI/4*stats[0].l/stats[0].KE;
	
	// Save data to HDD
	saveStatsData(c, stats[0] );    // Using 0 index to send aggregate data collected in first index
	saveYprofs(c, Yprof );
	
	return;
}
/*

/////////////////////////////////////////////////////////////////////////////////////
// Calculate Flame Surface properties
/////////////////////////////////////////////////////////////////////////////////////
	n = 1;
	cudaSetDevice(n-1);		// Device is set to 0 as the flame surface properties is currently designed to run on a single GPU

	// Define the stoichiometric value of the mixture fraction:
 	int n_Z = 6;
	double Zst[n_Z] = {0.05, 0.1, 0.2, 0.3, 0.4, 0.5};
	// int n_Z = 1;
	// double Zst[n_Z] = {0.5};
	
	// Declare Variables
	int j;
	double *SurfArea;
	double *f;		// Mixture fraction data (Z data, but renamed it for the surface area calcs)
	
	// Allocate memory
	cudaMallocManaged(&SurfArea, sizeof(double)*size_Stats);
	cudaMallocManaged(&f, sizeof(double)*NN);

// Loop through values of Zst
/////////////////////////////////////////////////////////////////////////////////////
	for (j = 0; j < n_Z; ++j){

		// Initialize surface properties to 0
		cudaMemset(SurfArea, 0.0, sizeof(double)*size_Stats);
		// cudaMemset(T4, 0.0, sizeof(double)*size_Stats);
		// cudaMemset(T5, 0.0, sizeof(double)*size_Stats);
		// cudaMemset(T5a, 0.0, sizeof(double)*size_Stats);
		// cudaMemset(T5b, 0.0, sizeof(double)*size_Stats);

// Enter timestepping loop
/////////////////////////////////////////////////////////////////////////////////////
		for (i = 0; i < size_Stats; ++i){

			// Calculate cation number based on how often data is saved
			c = i*n_save;

			// Import data to CPU memory for calculations
			importF(c, "z", f);

			// Calculate Integral Properties (uses only physical space variables)
			calcSurfaceArea(f, Zst[j], &SurfArea[i]);
			// calcSurfaceProps(plan, invplan, kx, u, v, w, z, Zst[j], &SurfArea[i], &T4[i], &T5[i], &T5a[i], &T5b[i]);

			cudaDeviceSynchronize();

			printf("The Surface Area of the flame is %g \n", SurfArea[i]);
			// printf("The value of Term IV is %g \n", T4[i]);
			// printf("The value of Term V is %g \n", T5[i]);
			// printf("The value of Term Va is %g \n", T5a[i]);
			// printf("The value of Term Vb is %g \n", T5b[i]);

		}
		// Exit timestepping loop

		// Save Zst-dependent data
		writeStats("Area", SurfArea, Zst[j]);
		// writeStats("IV", T4, Zst[j]);
		// writeStats("V", T5, Zst[j]);
		// writeStats("Va", T5a, Zst[j]);
		// writeStats("Vb", T5b, Zst[j]);

	}
	// Exit Zst loop

	// Deallocate Variables
	cudaFree(SurfArea);
	cudaFree(f);

//////////////////////////////////////////////////////////////////////////////////////
// Finished calculating surface properties
//////////////////////////////////////////////////////////////////////////////////////
	
	printf("Analysis complete, Data saved!\n");

	cudaDeviceReset();

	return 0;
}
*/
