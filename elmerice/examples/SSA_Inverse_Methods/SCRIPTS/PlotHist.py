#
# Make histogram plots from inverse methods results
#  Give a file that contains x y uobs vobs umod vmod
#
#
import numpy as np
from pylab import genfromtxt;
from scipy.stats import norm
import matplotlib.pyplot as plt
import sys

try:
	sys.argv[1]
except:
	print('error:  ')
	print('	provide a file name as argument')
	print('	must contain x y uobs vobs umod vmod')
	exit()

fname=sys.argv[1]
try:
	mat = genfromtxt(fname);
except:
	print('error:  ')
	print(' couldn t open %s'%(fname))


# Get Delta U and Delta V
u=mat[:,2]-mat[:,4];
v=mat[:,3]-mat[:,5];
du=np.sqrt(u*u + v*v)

# Compute RMS
npoints=np.size(mat,0)
rms=np.sqrt(np.sum(u*u + v*v )/npoints)
print(rms)

# Fit a normal distribution to the data:
mu_u, std_u = norm.fit(u)
mu_v, std_v = norm.fit(v)

plt.subplot(1,3,1)
# Plot the histogram.
plt.hist(du , bins=25, normed=True, alpha=0.6, color='g')
title = "du" 
plt.title(title)

plt.subplot(1,3,2)
# Plot the histogram.
plt.hist(u , bins=25, normed=True, alpha=0.6, color='g')

# Plot the PDF.
xmin, xmax = plt.xlim()
x = np.linspace(xmin, xmax, 100)
p = norm.pdf(x, mu_u, std_u)
plt.plot(x, p, 'k', linewidth=2)
title = "u: mu = %.2f,  std = %.2f" % (mu_u, std_u)
plt.title(title)

plt.subplot(1,3,3)
# Plot the histogram.
plt.hist(v , bins=25, normed=True, alpha=0.6, color='g')

# Plot the PDF.
xmin, xmax = plt.xlim()
x = np.linspace(xmin, xmax, 100)
p = norm.pdf(x, mu_v, std_v)
plt.plot(x, p, 'k', linewidth=2)
title = "v: mu = %.2f,  std = %.2f" % (mu_v, std_v)
plt.title(title)

plt.show()



