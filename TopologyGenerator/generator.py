import argparse

def printm(m):
    i = 0
    for k in m:
        print(i,"-->",k)
        i+=1

# Parse Arguments
ap = argparse.ArgumentParser()
ap.add_argument("-d", "--diameter", required=True, help="diameter of network",type=int)
ap.add_argument("-r","--range", required=True, help="range of each node",type=float)
ap.add_argument("-n","--noise", required=False, help="network noise, default = -50",type = float,default=-50)
args = vars(ap.parse_args())
d = args["diameter"]
r = args["range"]
noise = args["noise"]

# create grid
grid = []
s=0
for i in range(0,d):
    l = []

    for j in range(0,d):
        l.append(s)
        s+=1
    grid.append(l)

#Create connection Adjacency List
AdjList = []
for i in range(0,d*d):
    AdjList.append([])

#Calculate connections using pythagorean theorem
r_p = r**2.0
for i in range(0,d):
    for j in range(0,d):
        # Search on sub-grid
        x_start = j-r if j>=r else 0
        x_stop = j+r if j+r <= d-1 else d-1
        y_start = i-r if i>=r else 0
        y_stop = i+r if i+r <= d-1 else d-1

        for k in range(int(y_start),int(y_stop)+1):
            for l in range(int(x_start),int(x_stop)+1):
                if not(i==k and j==l):
                    if ((i-k)**2.0 + (j-l)**2.0 <= r_p ):
                        AdjList[grid[i][j]].append(grid[k][l])

#Print Comments
print("#Auto Generated Topology File")
print("#Topology Matrix: ",d,"*",d," Nodes")
print("#Radio Range: ",r)

#Print # of nodes
print("-n",d*d,'\n')

#Print node connections
for i in range(0,len(AdjList)):
    for con in AdjList[i]:
        print(i," ",con," ",noise)
    print("")