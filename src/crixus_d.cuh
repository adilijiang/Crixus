#ifndef CRIXUS_D_CUH
#define CRIXUS_D_CUH

#include "cuda_local.cuh"
#include "crixus.h"
#include "lock.cuh"

typedef union{
  float4 vec;
  float a[4];
} uf4;

typedef union{
  int4 vec;
  int a[4];
} ui4;

__global__ void set_bound_elem (uf4*, uf4*, float*, ui4*, unsigned int, float*, float*, float*, float*, Lock, int);

__global__ void swap_normals (uf4*, int);

__global__ void find_links(uf4 *pos, int nvert, uf4 *dmax, uf4 *dmin, float dr, int *newlink, int idim);

__global__ void periodicity_links (uf4*, ui4*, int, int, uf4*, uf4*, float, int*, int);

__global__ void calc_trisize(ui4 *ep, int *trisize, int nbe);

#ifndef bdebug
__global__ void calc_vert_volume (uf4*, uf4*, ui4*, float*, int*, uf4*, uf4*,  int, int, float, float, bool*);
#else
__global__ void calc_vert_volume (uf4*, uf4*, ui4*, float*, int*, uf4*, uf4*,  int, int, float, float, bool*, uf4*, float*);
#endif

__global__ void calc_ngridp (uf4*, unsigned int*, uf4*, uf4*, bool*, int*, int, float, float, int, int, float, Lock, int);

__device__ int calc_ggam(uf4 tpos, uf4 *pos, ui4 *ep, float *surf, uf4 *norm, uf4 *gpos, float *ggam, int *iggam, uf4 *dmin, uf4 *dmax, bool *per, int ngridp, float dr, float hdr, int iker, float eps, int nvert, int nbe, float krad, float iseed, bool ongpoint, int id);

__global__ void init_gpoints (uf4*, ui4*, float*, uf4*, uf4*, float*, float*, int*, uf4*, uf4*, bool*, int, float, float, int, float, int, int, float, float, int*, Lock, float*, int *);

__global__ void lobato_gpoints (uf4 *pos, ui4 *ep, float *surf, uf4 *norm, uf4 *gpos, float *gam, float *ggam, int *iggam, uf4 *dmin, uf4 *dmax, bool *per, int ngridp, float dr, float hdr, int iker, float eps, int nvert, int nbe, float krad, float seed, int *nrggam, Lock lock, float *deb, int *ilock);

__global__ void fill_fluid (uf4*, float, float, float, float, float, float, float, float, int*, int, Lock);

__device__ void gpu_sync (int*, int*);

__constant__ uf4 intri[17] = {{3.2906331E-2, 3.3333333E-1, 3.3333333E-1, 3.3333333E-1}, &
                              {1.0330731E-2, 0.2078003E-1, 4.8960998E-1, 4.8960998E-1}, &
															{2.2387247E-2, 0.9092621E-1, 4.5453689E-1, 4.8960998E-1}, &
															{3.0266125E-2, 1.9716663E-1, 4.0141668E-1, 4.0141668E-1}, &
															{3.0490967E-2, 4.8889669E-1, 2.5555165E-1, 2.5555165E-1}, &
															{2.4159212E-2, 6.4584411E-1, 1.7707794E-1, 1.7707794E-1}, &
															{1.6040803E-2, 7.7987789E-1, 1.1006105E-1, 1.1006105E-1}, &
															{0.8084580E-2, 8.8894275E-1, 0.5552862E-1, 0.5552862E-1}, &
															{0.2079362E-2, 9.7475627E-1, 0.1262186E-1, 0.1262186E-1}, &
															{0.3884876E-2, 0.0361141E-1, 3.9575478E-1, 6.0063379E-1}, &
															{2.5574160E-2, 1.3446675E-1, 3.0792998E-1, 5.5760326E-1}, &
															{0.8880903E-2, 0.1444602E-1, 2.6456694E-1, 7.2098702E-1}, &
															{1.6124546E-2, 0.4693357E-1, 3.5853935E-1, 5.9452706E-1}, &
															{0.2491941E-2, 0.0286112E-1, 1.5780740E-1, 8.3933147E-1}, &
															{1.8242840E-2, 2.2386142E-1, 0.7505059E-1, 7.0108797E-1}, &
															{2.0358563E-2, 0.3464707E-1, 1.4242160E-1, 8.2293132E-1}, &
															{0.3799928E-2, 0.1016111E-1, 0.6549462E-1, 9.2434425E-1} }

#endif
