#!/usr/bin/python

from TOSSIM import *
import sys, os
import random

t = Tossim([])
f = sys.stdout  # open('./logfile.txt','w')
SIM_END_TIME = 910 * t.ticksPerSecond()

print
"TicksPerSecond : ", t.ticksPerSecond(), "\n"

# Debug Channels
t.addChannel("Boot", f)
t.addChannel("Routing",f)
t.addChannel("NotifyParentMsg",f)
# t.addChannel("Radio",f)
# t.addChannel("SRTreeC",f)
# t.addChannel("PacketQueueC",f)
# t.addChannel("Timing",f)
t.addChannel("Measure", f)
t.addChannel("Root", f)
t.addChannel("Query", f)

#default file
file = "topology.txt"
#file from argument 
if(len(sys.argv)==2):
	file = sys.argv[1]

print("Using Topology File: ",file)

#open topology file
topo = open(file, "r")
#check if topology file opened
if topo is None:
    print
    "Topology file not found!!! \n"

r = t.radio()
lines = topo.readlines()

#find num of nodes
for line in lines:
    s=line.split()
    if (len(s)>0 and s[0]=="-n"):
        nodes = int(s[1])
        lines[lines.index(line)] = ' '

#print topology file comments
for line in lines:
    s=line.split()
    if (line[0] == "#"):
        print(line.replace("\n",""))
        lines[lines.index(line)]=' '

#spawn nodes
for i in range(0, nodes):
    m = t.getNode(i)
    m.bootAtTime(10*t.ticksPerSecond() + i)

#route nodes
for line in lines:
    s = line.split()
    if (len(s) > 0):
        # print " ", s[0], " ", s[1], " ", s[2];
        r.add(int(s[0]), int(s[1]), float(s[2]))

mTosdir = os.getenv("TINYOS_ROOT_DIR")
noiseF = open(mTosdir + "/tos/lib/tossim/noise/meyer-heavy.txt", "r")
lines = noiseF.readlines()

for line in lines:
    str1 = line.strip()
    if str1:
        val = int(str1)
        for i in range(0, nodes):
            t.getNode(i).addNoiseTraceReading(val)
noiseF.close()
for i in range(0, nodes):
    t.getNode(i).createNoiseModel()

ok = False
# if(t.getNode(0).isOn()==True):
#	ok=True
h = True
while (h):
    try:
        h = t.runNextEvent()
    # print h
    except:
        print
        sys.exc_info()
    #		e.print_stack_trace()

    if (t.time() >= SIM_END_TIME):
        h = False
    if (h <= 0):
        ok = False