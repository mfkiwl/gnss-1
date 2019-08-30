#ifndef STRUCT_DEF
#define STRUCT_DEF

typedef struct gpuinfo{
	int *gpunum;				// Current GPU number
	int *ny;						// Number of grid points in the Y direction for the nth GPU
	int *nx; 					  // Number of grid points in the X direction for GPU n
	int *start_y;			  // Starting index of data in the y-direction for this gpu
	int *start_x;			  // Starting index of data in x-direction for this gpu
	int nGPUs;				  // Number of GPUs on this node 
} gpuinfo;

typedef struct statistics{
	double **Vrms;							// RMS velocity
	double **KE;								// Turbulent kinetic energy
	double **epsilon;					  // Dissipation rate of tke
	double **eta;							  // Kolmogorov length Scale
	double **l;								  // Integral length scale
	double **lambda;						// Taylor Micro scale
	double **chi;							  // Scalar dissipation rate
	double **area_scalar;			  // Area of the iso-scalar surface
	double **area_tnti;				  // Area of the iso-enstrophy surface (Turbulent/non-turbulent interface)
	double **energy_spect;			// Spectral energy in spherical wave number shells
}statistics;

typedef struct fftinfo{
	cufftHandle *p1d;									  // cuFFT Plan info for 1D Transform
	cufftHandle *p2d;									  // cuFFT Plan info for 2D Transform
	cufftHandle *invp2d;								// cuFFT Plan info for inverse 2D Transform
	size_t *wsize_f;										// Size of workspace needed for forward transform
	size_t *wsize_i;										// Size of workspace needed for inverse transform
	cufftDoubleComplex **wspace;				// Pointer to cuFFT workspace to perform FFTs
	cufftDoubleComplex **temp;					// Pointer to temporary array used in transpose
	cufftDoubleComplex **temp_reorder;	// Pointer to temporary array used in transpose
}fftinfo;

typedef struct fielddata{
	cufftDoubleReal **u;					// u component of velocity in physical space
	cufftDoubleReal **v;					// v component of velocity in physical space
	cufftDoubleReal **w;					// w component of velocity in physical space
	cufftDoubleReal **s;					// scalar field in physical space
	cufftDoubleComplex **uh;			// u_hat - u component of field in Fourier Space
	cufftDoubleComplex **vh;			// v_hat - v component of field in Fourier Space
	cufftDoubleComplex **wh;			// w_hat - w component of field in Fourier Space
	cufftDoubleComplex **sh;			// s_hat - scalar field in Fourier Space
}fielddata;

typedef struct gridinfo{
	double nx;					// Number of grid points in x-direction
	double ny;					// Number of grid points in y-direction
	double nz;					// Number of grid points in z-direction
	double lx;					// Length of computational domain in x-direction
	double ly;					// Length of computational domain in y-direction
	double lz;					// Length of computational domain in z-direction
	double dx;					// Grid spacing in x-direction
	double dy;					// Grid spacing in y-direction
	double dz;					// Grid spacing in z-direction
	double *x;					// Vector of grid points in x-direction
	double *y;					// Vector of grid points in y-direction
	double *z;					// Vector of grid points in z-direction
	double *kx;					// Vector of wave numbers in x-direction
	double *ky;					// Vector of wave numbers in y-direction
	double *kz;					// Vector of wave numbers in z-direction
}gridinfo;

#endif