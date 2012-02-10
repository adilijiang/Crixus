#ifndef CRIXUS_D_CU
#define CRIXUS_D_CU

#include <cuda.h>
#include "lock.cuh"
#include "crixus_d.cuh"
#include "return.h"
#include "crixus.h"

__global__ void set_bound_elem (uf4 *pos, uf4 *norm, float *surf, ui4 *ep, unsigned int nbe, float *xminp, float *xminn, float *nminp, float*nminn, Lock lock, int nvert)
{
	float ddum[3];
	unsigned int i = blockIdx.x*blockDim.x+threadIdx.x;
	__shared__ float xminp_c[threadsPerBlock];
	__shared__ float xminn_c[threadsPerBlock];
	__shared__ float nminp_c[threadsPerBlock];
	__shared__ float nminn_c[threadsPerBlock];
	float xminp_t;
	float xminn_t;
	float nminp_t;
	float nminn_t;
	int i_c = threadIdx.x;
	xminp_t = *xminp;
	xminn_t = *xminn;
	nminp_t = *nminp;
	nminn_t = *nminn;
	while(i<nbe){
		//formula: a = 1/4 sqrt(4*a^2*b^2-(a^2+b^2-c^2)^2)
		float a2 = 0.;
		float b2 = 0.;
		float c2 = 0.;
		ddum[0] = 0.;
		ddum[1] = 0.;
		ddum[2] = 0.;
		for(unsigned int j=0; j<3; j++){
			ddum[j] += pos[ep[i].a[0]].a[j]/3.;
			ddum[j] += pos[ep[i].a[1]].a[j]/3.;
			ddum[j] += pos[ep[i].a[2]].a[j]/3.;
			a2 += pow(pos[ep[i].a[0]].a[j]-pos[ep[i].a[1]].a[j],2);
			b2 += pow(pos[ep[i].a[1]].a[j]-pos[ep[i].a[2]].a[j],2);
			c2 += pow(pos[ep[i].a[2]].a[j]-pos[ep[i].a[0]].a[j],2);
		}
		if(norm[i].a[2] > 1e-5 && xminp_t > ddum[2]){
			xminp_t = ddum[2];
			nminp_t = norm[i].a[2];
		}
		if(norm[i].a[2] < -1e-5 && xminn_t > ddum[2]){
			xminn_t = ddum[2];
			nminn_t = norm[i].a[2];
		}
		surf[i] = 0.25*sqrt(4.*a2*b2-pow(a2+b2-c2,2));
    for(int j=0; j<3; j++)
		  pos[i+nvert].a[j] = ddum[j];
		i += blockDim.x*gridDim.x;
	}

	xminp_c[i_c] = xminp_t;
	xminn_c[i_c] = xminn_t;
	nminp_c[i_c] = nminp_t;
	nminn_c[i_c] = nminn_t;
	__syncthreads();

	int j = blockDim.x/2;
	while (j!=0){
		if(i_c < j){
			if(xminp_c[i_c+j] < xminp_c[i_c]){
				xminp_c[i_c] = xminp_c[i_c+j];
				nminp_c[i_c] = nminp_c[i_c+j];
			}
			if(xminn_c[i_c+j] < xminn_c[i_c]){
				xminn_c[i_c] = xminn_c[i_c+j];
				nminn_c[i_c] = nminn_c[i_c+j];
			}
		}
		__syncthreads();
		j /= 2;
	}

	if(i_c == 0){
		lock.lock();
		if(xminp_c[0] < *xminp){
			*xminp = xminp_c[0];
			*nminp = nminp_c[0];
		}
		if(xminn_c[0] < *xminn){
			*xminn = xminn_c[0];
			*nminn = nminn_c[0];
		}
		lock.unlock();
	}
}

__global__ void swap_normals (uf4 *norm, int nbe)
{
	unsigned int i = blockIdx.x*blockDim.x+threadIdx.x;
	while(i<nbe){
    for(int j=0; j<3; j++)
		  norm[i].a[j] *= -1.;
		i += blockDim.x*gridDim.x;
	}
}

__global__ void periodicity_links (uf4 *pos, ui4 *ep, int nvert, int nbe, uf4 *dmax, uf4 *dmin, float dr, int *sync_i, int *sync_o, int *newlink, int idim, Lock lock)
{
	//find corresponding vertices
	unsigned int i = blockIdx.x*blockDim.x+threadIdx.x;
	unsigned int i_c = threadIdx.x;
	while(i<nvert){
		newlink[i] = 0;
		i += blockDim.x*gridDim.x;
	}

//	gpu_sync(sync_i, sync_o);
	if(i_c==0){
		lock.lock();
		lock.unlock();
	}
	__syncthreads();

	i = blockIdx.x*blockDim.x+threadIdx.x;
	while(i<nvert){
		if(fabs(pos[i].a[idim]-(*dmax).a[idim])<1e-5*dr){
			for(unsigned int j=0; j<nvert; j++){
				if(j==i) continue;
				if(sqrt(pow(pos[i].a[(idim+1)%3]-pos[j].a[(idim+1)%3],(float)2.)+ \
				        pow(pos[i].a[(idim+2)%3]-pos[j].a[(idim+2)%3],(float)2.)+ \
								pow(pos[j].a[idim      ]- (*dmin).a[idim]      ,(float)2.) ) < 1e-4*dr){
					newlink[i] = j;
					//"delete" vertex
					for(int k=0; k<3; k++)
						pos[i].a[k] = -1e10;
					break;
				}
				if(j==nvert-1){
					// cout << " [FAILED]" << endl;
					return; //NO_PER_VERT;
				}
			}
		}
		i += blockDim.x*gridDim.x;
	}

//	gpu_sync(sync_i, sync_o);
	if(i_c==0){
		lock.lock();
		lock.unlock();
	}
	__syncthreads();

	//relink
	i = blockIdx.x*blockDim.x+threadIdx.x;
	while(i<nbe){
    for(int j=0; j<3; j++){
		  if(newlink[ep[i].a[j]] != -1)
        ep[i].a[j] = newlink[ep[i].a[j]];
    }
		i += blockDim.x*gridDim.x;
	}

	return;
}

#ifndef bdebug
__global__ void calc_vert_volume (uf4 *pos, uf4 *norm, ui4 *ep, float *vol, int *trisize, uf4 *dmin, uf4 *dmax, int *sync_i, int *sync_o, int nvert, int nbe, float dr, float eps, bool *per, Lock lock)
#else
__global__ void calc_vert_volume (uf4 *pos, uf4 *norm, ui4 *ep, float *vol, int *trisize, uf4 *dmin, uf4 *dmax, int *sync_i, int *sync_o, int nvert, int nbe, float dr, float eps, bool *per, Lock lock, uf4 *debug, float* debugp)
#endif
{
	//get neighbouring vertices
	int i = blockIdx.x*blockDim.x+threadIdx.x;
	int i_c = threadIdx.x;
	while(i<nvert){
		trisize[i] = 0;
		i += blockDim.x*gridDim.x;
	}

//	gpu_sync(sync_i, sync_o);
	if(i_c==0){
		lock.lock();
		lock.unlock();
	}
	__syncthreads();

	i = blockIdx.x*blockDim.x+threadIdx.x;
	while(i<nbe){
		for(unsigned int j=0; j<3; j++){
			atomicAdd(&trisize[ep[i].a[j]],1);
		}
		i += blockDim.x*gridDim.x;
	}

//	gpu_sync(sync_i, sync_o);
	if(i_c==0){
		lock.lock();
		lock.unlock();
	}
	__syncthreads();

	//sort neighbouring vertices
	//calculate volume (geometry factor)
	unsigned int gsize = gres*2+1; //makes sure that grid is large enough
	float gdr = dr/(float)gres;
	float vgrid;
	float cvec[trimax][12][3];
	int tri[trimax][3];
	float avnorm[3];
	bool first[trimax];
	float vnorm;
	bool closed;
	int iduma[3];
	float sp;

	i = blockIdx.x*blockDim.x+threadIdx.x;
	while(i<nvert){

		//vertex has been deleted
		if(pos[i].a[0] < -1e9){
			i += blockDim.x*gridDim.x;
			continue;
		}

		//initialize variables
		closed = true;
		vol[i] = 0.;
		unsigned int tris = trisize[i];
    if(tris > trimax)
      return; //exception needs to be thrown
		for(unsigned int j=0; j<tris; j++)
			first[j] = true;
		for(unsigned int j=0; j<3; j++)
      avnorm[j] = 0.;

		//find connected faces
		unsigned int itris = 0;
		for(unsigned int j=0; j<nbe; j++){
			for(unsigned int k=0; k<3; k++){
				if(ep[j].a[k] == i){
					tri[itris][0] = ep[j].a[(k+1)%3];
					tri[itris][1] = ep[j].a[(k+2)%3];
					tri[itris][2] = j;
					itris++;
				}
			}
		}

		//try to put neighbouring faces next to each other
		for(unsigned int j=0; j<tris; j++){
			for(unsigned int k=j+1; k<tris; k++){
				if(tri[j][1] == tri[k][0]){
					if(k!=j+1){
						for(int l=0; l<3; l++){
							iduma[l] = tri[j+1][l];
							tri[j+1][l] = tri[k][l];
							tri[k][l] = iduma[l];
						}
					}
					break;
				}
				if(tri[j][1] == tri[k][1]){
					iduma[0] = tri[k][1];
					iduma[1] = tri[k][0];
					iduma[2] = tri[k][2];
					for(int l=0; l<3; l++){
						tri[k][l] = tri[j+1][l];
						tri[j+1][l] = iduma[l];
					}
					break;
				}
				if(k==tris-1) closed = false;
			}
		}
		if(tri[0][0] != tri[tris-1][1]){
			closed = false;
		}

		//start big loop over all numerical integration points
		for(unsigned int k=0; k<gsize; k++){
		for(unsigned int l=0; l<gsize; l++){
		for(unsigned int m=0; m<gsize; m++){

			float gp[3]; //gridpoint in coordinates relative to vertex
			gp[0] = (((float)k-(float)(gsize-1)/2))*gdr;
			gp[1] = (((float)l-(float)(gsize-1)/2))*gdr;
			gp[2] = (((float)m-(float)(gsize-1)/2))*gdr;
			vgrid = 0.;

#ifdef bdebug
			if(i==bdebug){
			for(int j=0; j<3; j++) debug[k+l*gsize+m*gsize*gsize].a[j] = gp[j] + pos[i].a[j];
			debug[k+l*gsize+m*gsize*gsize].a[3] = -1.;
			for(int j=0; j<100; j++) debugp[j] = 0.;
			}
			if(i==bdebug) debugp[0] = tris;
#endif

			//create cubes
			for(unsigned int j=0; j<tris; j++){
				if(k+l+m==0){
					//setting up cube directions
					for(unsigned int n=0; n<3; n++) cvec[j][2][n] = norm[tri[j][2]].a[n]; //normal of boundary element
					vnorm = 0.;
					for(unsigned int n=0; n<3; n++){
						cvec[j][0][n] = pos[tri[j][0]].a[n]-pos[i].a[n]; //edge 1
						if(per[n]&&fabs(cvec[j][0][n])>2*dr)	cvec[j][0][n] += sgn(cvec[j][0][n])*(-(*dmax).a[n]+(*dmin).a[n]); //periodicity
						vnorm += pow(cvec[j][0][n],2);
					}
					vnorm = sqrt(vnorm);
					for(unsigned int n=0; n<3; n++) cvec[j][0][n] /= vnorm; 
					for(unsigned int n=0; n<3; n++)	cvec[j][1][n] = cvec[j][0][(n+1)%3]*cvec[j][2][(n+2)%3]-cvec[j][0][(n+2)%3]*cvec[j][2][(n+1)%3]; //cross product of normal and edge1
					vnorm = 0.;
					for(unsigned int n=0; n<3; n++){
						cvec[j][3][n] = pos[tri[j][1]].a[n]-pos[i].a[n]; //edge 2
						if(per[n]&&fabs(cvec[j][3][n])>2*dr)	cvec[j][3][n] += sgn(cvec[j][3][n])*(-(*dmax).a[n]+(*dmin).a[n]); //periodicity
						vnorm += pow(cvec[j][3][n],2);
						avnorm[n] -= norm[tri[j][2]].a[n];
					}
					vnorm = sqrt(vnorm);
					for(unsigned int n=0; n<3; n++) cvec[j][3][n] /= vnorm; 
					for(unsigned int n=0; n<3; n++)	cvec[j][4][n] = cvec[j][3][(n+1)%3]*cvec[j][2][(n+2)%3]-cvec[j][3][(n+2)%3]*cvec[j][2][(n+1)%3]; //cross product of normal and edge2
				}
				//filling vgrid
				bool incube[5] = {false, false, false, false, false};
				for(unsigned int n=0; n<5; n++){
					sp = 0.;
					for(unsigned int o=0; o<3; o++) sp += gp[o]*cvec[j][n][o];
					if(fabs(sp)<=dr/2.+eps) incube[n] = true;
				}
				if((incube[0] && incube[1] && incube[2]) || (incube[2] && incube[3] && incube[4])){
					vgrid = 1.;
#ifdef bdebug
			if(i==bdebug) debug[k+l*gsize+m*gsize*gsize].a[3] = 1.;
#endif
					if(k+l+m!=0) break; //makes sure that in the first grid point we loop over all triangles j s.t. values are initialized correctly.
				}
			}
			//end create cubes

			//remove points based on planes (voronoi diagram & walls)
			float tvec[3][3];
			for(unsigned int j=0; j<tris; j++){
				if(vgrid<eps) break; //gridpoint already empty
				if(first[j]){
					first[j] = false;
					//set up plane normals and points
					for(unsigned int n=0; n<3; n++){
						cvec[j][5][n] = pos[tri[j][0]].a[n]-pos[i].a[n]; //normal of plane voronoi
						if(per[n]&&fabs(cvec[j][5][n])>2*dr)	cvec[j][5][n] += sgn(cvec[j][5][n])*(-(*dmax).a[n]+(*dmin).a[n]); //periodicity
						cvec[j][6][n] = pos[i].a[n]+cvec[j][5][n]/2.; //position of plane voronoi
						tvec[0][n] = cvec[j][5][n]; // edge 1
						tvec[1][n] = pos[tri[j][1]].a[n]-pos[i].a[n]; // edge 2
						if(per[n]&&fabs(tvec[1][n])>2*dr)	tvec[1][n] += sgn(tvec[1][n])*(-(*dmax).a[n]+(*dmin).a[n]); //periodicity
						if(!closed){
							cvec[j][7][n] = tvec[1][n]; //normal of plane voronoi 2
							cvec[j][8][n] = pos[i].a[n]+cvec[j][7][n]/2.; //position of plane voronoi 2
						}
						tvec[2][n] = avnorm[n]; // negative average normal
					}
					for(unsigned int n=0; n<3; n++){
						for(unsigned int k=0; k<3; k++){
							cvec[j][k+9][n] = tvec[k][(n+1)%3]*tvec[(k+1)%3][(n+2)%3]-tvec[k][(n+2)%3]*tvec[(k+1)%3][(n+1)%3]; //normals of tetrahedron planes
						}
					}
					sp = 0.;
					for(unsigned int n=0; n<3; n++) sp += norm[tri[j][2]].a[n]*cvec[j][9][n]; //test whether normals point inward tetrahedron, if no flip normals
					if(sp > 0.){
						for(unsigned int k=0; k<3; k++){
							for(unsigned int n=0; n<3; n++)	cvec[j][k+9][n] *= -1.;
						}
					}
				}

			  //remove unwanted points and sum up for volume
				//voronoi plane
				for(unsigned int n=0; n<3; n++) tvec[0][n] = gp[n] + pos[i].a[n] - cvec[j][6][n];
				sp = 0.;
				for(unsigned int n=0; n<3; n++) sp += tvec[0][n]*cvec[j][5][n];
				if(sp>0.+eps){
					vgrid = 0.;
#ifdef bdebug
			if(i==bdebug) debug[k+l*gsize+m*gsize*gsize].a[3] = 0.;
#endif
					break;
				}
				else if(fabs(sp) < eps){
					vgrid /= 2.;
				}
				//voronoi plane 2
				if(!closed){
					for(unsigned int n=0; n<3; n++) tvec[0][n] = gp[n] + pos[i].a[n] - cvec[j][8][n];
					sp = 0.;
					for(unsigned int n=0; n<3; n++) sp += tvec[0][n]*cvec[j][7][n];
					if(sp>0.+eps){
						vgrid = 0.;
						break;
					}
					else if(fabs(sp) < eps){
						vgrid /= 2.;
					}
				}
				//walls
				bool half = false;
				for(unsigned int o=0; o<3; o++){
					sp = 0.;
					for(unsigned int n=0; n<3; n++) sp += gp[n]*cvec[j][9+o][n];
					if(sp<0.-eps) break;
					if(fabs(sp)<eps && o==0) half=true;
					if(o==2 && !half){
						vgrid = 0.;
#ifdef bdebug
			if(i==bdebug) debug[k+l*gsize+m*gsize*gsize].a[3] = 0.;
#endif
						break;
					}
					else if(o==2 && half){
						vgrid /= 2.;
					}
				}
				if(vgrid < eps) break;

				//volume sum
				if(j==tris-1)	vol[i] += vgrid;
			}

		}
		}
		}
		//end looping through all gridpoints

		//calculate volume
		vol[i] *= pow(dr/(float)gres,3);

		i += blockDim.x*gridDim.x;
	}
}

__global__ void calc_ngridp (uf4 *pos, unsigned int *igrid, uf4 *dmin, uf4 *dmax, bool *per, int *ngridp, int maxgridp, float dr, float eps, int nvert, int nbe, float krad, Lock lock, int igrids){
	const unsigned int uibs = 8*sizeof(unsigned int);
	unsigned int byte[uibs];
	for(int i=0; i<uibs; i++)
		byte[i] = 1<<i;
	int id = blockIdx.x*blockDim.x+threadIdx.x;
	int i_c = threadIdx.x;
	int idim = (floor(((*dmax).a[1]+eps-(*dmin).a[1])/dr)+1)*(floor(((*dmax).a[0]+eps-(*dmin).a[0])/dr)+1);
	int jdim =  floor(((*dmax).a[0]+eps-(*dmin).a[0])/dr)+1;
	__shared__ int ngridpl[threadsPerBlock];
	ngridpl[i_c] = 0;

	while(id<maxgridp){
		int ipos[3];
		ipos[2] = id/idim;
		int tmp = id%idim;
		ipos[1] = tmp/jdim;
		ipos[0] = tmp%jdim;
		float gpos[3], rvec[3];
		for(int i=0; i<3; i++) gpos[i] = (*dmin).a[i] + ((float)ipos[i])*dr;
		for(int i=0; i<nvert+nbe; i++){
			bool bbreak = false;
			for(int j=0; j<3; j++){
				rvec[j] = gpos[j] - pos[i].a[j];
				//this introduces a min size for the domain, check it
				if(per[j]&&fabs(rvec[j])>2*(krad+dr))	rvec[j] += sgn(rvec[j])*(-(*dmax).a[j]+(*dmin).a[j]); //periodicity
				if(fabs(rvec[j]) > krad+dr+eps){
					bbreak = true;
					break;
				}
			}
			if(bbreak) continue;
			if(sqrt(sqr(rvec[0])+sqr(rvec[0])+sqr(rvec[2])) <= krad+dr+eps){
				ngridpl[i_c] += 1;
				int ida = id/uibs;
				int idi = id%uibs;
				unsigned int tbyte = byte[idi];
				atomicOr(&igrid[ida],tbyte);
				break;
			}
		}
		id += blockDim.x*gridDim.x;
	}

	__syncthreads();
	int j = blockDim.x/2;
	while (j!=0){
		if(i_c < j){
			ngridpl[i_c] += ngridpl[i_c+j];
		}
		__syncthreads();
		j /= 2;
	}

	if(i_c == 0){
		lock.lock();
		*ngridp += ngridpl[0];
		lock.unlock();
	} 
}

__device__ float rand(float seed){
	const unsigned long m = 1UL<<32; //2^32
	const unsigned long a = 1664525UL;
	const unsigned long c = 1013904223UL;
	unsigned long xn = (unsigned long) (seed*float(m));
	unsigned long xnp1 = (a*xn+c)%m;
	return (float)((float)xnp1/(float)m);
}

/*__device__ inline float dot(uf4 a, uf4 b){
	float spv=0;
	for(int i=0; i<3; i++)
		spv += a.a[i]*b.a[i];
	return spv;
}*/

__device__ inline float wendland_kernel(float q, float h){
	const float alpha = 21./16./3.1415926;
	return alpha/(sqr(sqr(h)))*sqr(sqr((1.-q/2.)))*(1.+2.*q);
}

__global__ void init_gpoints (uf4 *pos, ui4 *ep, float *surf, uf4 *norm, uf4 *gpos, float *gam, float *ggam, uf4 *dmin, uf4 *dmax, bool *per, int ngridp, float dr, float hdr, int iker, float eps, int nvert, int nbe, float krad, float seed, int *nrggam, Lock lock){
	int id = blockIdx.x*blockDim.x+threadIdx.x;
	int i_c = blockIdx.x;
	__shared__ int nrggaml[threadsPerBlock];
	nrggaml[i_c] = 0;
	int idim = (floor(((*dmax).a[1]+eps-(*dmin).a[1])/dr)+1)*(floor(((*dmax).a[0]+eps-(*dmin).a[0])/dr)+1);
	int jdim =  floor(((*dmax).a[0]+eps-(*dmin).a[0])/dr)+1;
	float h = hdr*dr;
	//initializing random number generator
	float iseed = (float)id/((float)(blockDim.x*gridDim.x))+seed;
	if(iseed > 1.)
		iseed -= 1.;
	iseed = rand(iseed);
	for(int i=0; i<(int)(iseed*20.); i++)
		iseed = rand(iseed);
	//calculate position and neighbours, initialize gam for those who don't have neighbours
	//find boundary elements and calculate ggam_{pb}
	while(id < ngridp){
		//calculate position
		int ipos[3];
		float tpos[3];
		ipos[2] = (int)(gpos[id].a[3])/idim;
		int tmp = (int)(gpos[id].a[3])%idim;
		ipos[1] = tmp/jdim;
		ipos[0] = tmp%jdim;
		for(int i=0; i<3; i++){
			gpos[id].a[i] = (*dmin).a[i] + ((float)ipos[i])*dr;
			tpos[i] = gpos[id].a[i];
		}
		//find neighbouring boundary elements
		int nlink = 0;
		int link[maxlink];
		for(int i=0; i<nvert+nbe; i++){
			float rvecn = 0.;
			for(int j=0; j<3; j++) rvecn += sqr(tpos[j]-pos[i].a[j]);
			if(sqrt(rvecn) <= krad+eps){
				if(i>=nvert){
					bool found = false;
					for(int j=0; j<nlink; j++){
						if(link[j] == i){
							found = true;
							break;
						}
					}
					if(!found){
						link[nlink] = i;
						nlink++;
						if(nlink>maxlink)
							return;
					}
				}
				else{
					for(int j=0; j<nbe; j++){
						for(int k=0; k<3; k++){
							if(ep[j].a[k] == i){
								bool found = false;
								for(int j=0; j<nlink; j++){
									if(link[j] == i){
										found = true;
										break;
									}
								}
								if(!found){
									link[nlink] = i;
									nlink++;
									if(nlink>maxlink)
										return;
								}
								break;
							}
						}
					}
				}
			}
		}
		//calculate ggam_{pb}
		for(int i=0; i<nlink; i++){
			int ib = link[i];
			float nggam = 0.;
			float vol = surf[ib]/(float)ipoints;
			uf4 edges[3];
			for(int j=0; j<3; j++){
				edges[0].a[j] = pos[ep[ib].a[1]].a[j] - pos[ep[ib].a[0]].a[j];
				edges[1].a[j] = pos[ep[ib].a[2]].a[j] - pos[ep[ib].a[0]].a[j];
			}
			uf4 bv[2]; //bv ... basis vectors
			float vnorm=0.;
			float sps[5];
			for(int j=0; j<5; j++)
				sps[j] = 0.;
			for(int j=0; j<3; j++){
				bv[1].a[j] = -edges[2].a[j];
				vnorm+=sqr(bv[0].a[j]);
				sps[0] += edges[0].a[j]*edges[0].a[j];
				sps[1] += edges[0].a[j]*edges[1].a[j];
				sps[3] += edges[1].a[j]*edges[1].a[j];
			}
			vnorm = sqrt(vnorm);
			float sp=0.;
			for(int j=0; j<3; j++){
				bv[0].a[j] /= vnorm;
				sp += bv[1].a[j]*edges[0].a[j];
			}
			vnorm = 0.;
			for(int j=0; j<3; j++){
				bv[1].a[j] -= sp*edges[0].a[j];
				vnorm += sqr(bv[1].a[j]);
			}
			vnorm = sqrt(vnorm);
			for(int j=0; j<3; j++)
				bv[1].a[j] /= vnorm;
			for(int j=0; j<ipoints; j++){
				bool intri = false;
				while(intri){
					float tpi[2];
					iseed = rand(iseed);
					tpi[0] = iseed;
					iseed = rand(iseed);
					tpi[1] = iseed;
					uf4 tp;
					sps[2] = 0.;
					sps[4] = 0.;
					for(int k=0; k<3; k++){
						tp.a[k] = tpi[0]*bv[0].a[k] + tpi[1]*bv[1].a[k];
						edges[2].a[k] = tp.a[k] - pos[ep[ib].a[0]].a[k];
						sps[2] += edges[0].a[k]*edges[2].a[k];
						sps[4] += edges[1].a[k]*edges[2].a[k];
					}
					float invdet = 1./(sps[0]*sps[3]-sps[1]*sps[1]);
					float u = (sps[3]*sps[2]-sps[1]*sps[4])*invdet;
					float v = (sps[0]*sps[4]-sps[1]*sps[2])*invdet;
					if(u >= 0 && v >= 0 && u + v < 1)
						intri = true;
					if(!intri)
						continue;
					float q = 0.;
					for(int k=0; k<3; k++)
						q += sqr(tp.a[k]-tpos[k]);
					q = sqrt(q)/h;
					switch(iker){
						case 1:
						default:
							nggam += wendland_kernel(q,h);
					}
				}
			}
			for(int j=0; j<3; j++)
				ggam[id*maxlink*3+i*3+j]  += nggam * vol * norm[ib].a[j];
		}
		for(int i=nlink; i<maxlink; i++)
			ggam[id*maxlink*3+i*3] = -1e10;
		nrggaml[i_c] += nlink;
		id+=blockDim.x*gridDim.x;
	}

	__syncthreads();
	int j = blockDim.x/2;
	while (j!=0){
		if(i_c < j){
			nrggaml[i_c] += nrggaml[i_c+j];
		}
		__syncthreads();
		j /= 2;
	}

	if(i_c == 0){
		lock.lock();
		*nrggam += nrggaml[0];
		lock.unlock();
	} 
}

__global__ void fill_fluid (uf4 *fpos, float xmin, float xmax, float ymin, float ymax, float zmin, float zmax, float eps, float dr, int *nfib, int fmax, Lock lock)
{
	//this can be a bit more complex in order to fill complex geometries
	__shared__ int nfib_cache[threadsPerBlock];
	int idim = (floor((ymax+eps-ymin)/dr)+1)*(floor((xmax+eps-xmin)/dr)+1);
	int jdim =  floor((xmax+eps-xmin)/dr)+1;
	int i, j, k, tmp, nfib_tmp;
	int tid = threadIdx.x;

	nfib_tmp = 0;
	int id = blockIdx.x*blockDim.x+threadIdx.x;
	while(id<fmax){
		k = id/idim;
		tmp = id%idim;
		j = tmp/jdim;
		i = tmp%jdim;
		fpos[id].a[0] = xmin + (float)i*dr;
		fpos[id].a[1] = ymin + (float)j*dr;
		fpos[id].a[2] = zmin + (float)k*dr;
		nfib_tmp++;
		//if position should not be filled use a[0] = -1e10 and do not increment nfib_tmp
		id += blockDim.x*gridDim.x;
	}
	nfib_cache[tid] = nfib_tmp;

	__syncthreads();

	j = blockDim.x/2;
	while (j!=0){
		if(tid < j)
			nfib_cache[tid] += nfib_cache[tid+j];
		__syncthreads();
		j /= 2;
	}

	if(tid == 0){
		lock.lock();
		*nfib += nfib_cache[0];
		lock.unlock();
	}
}

//Implemented according to: Inter-Block GPU Communication via Fast Barrier Synchronization, Shucai Xiao and Wu-chun Feng, Department of Computer Science, Virginia Tech, 2009
//The original implementation doesn't work. For now lock is used.
__device__ void gpu_sync (int *sync_i, int *sync_o)
{
	int tid_in_block = threadIdx.x;
	int bid = blockIdx.x;
	int nblock = gridDim.x;

	//sync thread 0 in all blocks
	if(tid_in_block == 0){
		sync_i[bid] = 1;
		sync_o[bid] = 0;
	}
	
	if(bid == 0){
		int i = tid_in_block;
		while (i<nblock) {
			while(sync_i[i] != 1)
				;
			i += blockDim.x;
		}
		__syncthreads();

		i = tid_in_block;
		while (i<nblock) {
			sync_o[i] = 1;
			sync_i[i] = 0;
			i += blockDim.x;
		}
	}

//this last part causes an infinite loop, why?
	//sync block
	if(tid_in_block == 0 && bid == 1){
		while (sync_o[bid] != 1)
      			;
	}

	__syncthreads();

}

#endif
