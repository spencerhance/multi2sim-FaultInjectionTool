#!/usr/bin/env python

import sys
import os
from optparse import OptionParser
import random
#from __future__ import print_function
from subprocess import call

bench_list=('BinarySearch',
            'BinomialOption',
            'BitonicSort',
            'BlackScholes',
            'BoxFilter',
            'DCT',
            'DwtHaar1D',
            'FastWalshTransform',
            'FloydWarshall',
            'Histogram',
            'MatrixMultiplication',
            'MatrixTranspose',
            'PrefixSum',
            'RadixSort',
            'RecursiveGaussian',
            'Reduction',
            'ScanLargeArrays',
            'SobelFilter',
            'URNG')

def OptionParsing():
    usage = "usage: %prog [options] <fault_type> <num_faults>"
    parser = OptionParser(usage=usage)
    parser.add_option("-b", "--bench-name", dest="benchmark",
                      help="Benchmark to generate faults for", metavar="BENCHMARK_NAME")
    parser.add_option("-f", "--faults-dir", dest="faults_dir",
                      help="Directory where the faults will be located", metavar="FAULTS_DIR")        
    (options, args) = parser.parse_args()

    # Get benchmark name
    if options.benchmark:
        benchmark = options.benchmark
        # write a function to check the name of the benchmark checks out
        if CheckBenchName(benchmark) is False and benchmark != 'all':
            print benchmark, " is not in the bench list"
            parser.error("Wrong benchmark name")
    else:
        benchmark = "all"
        
    # Get directory for faults
    if options.faults_dir:
        faults_dir = options.faults_dir
        if os.path.isdir(options.faults_dir) is False:
            parser.error(faults_dir + " is not a directory")
    else:
        faults_dir = os.getcwd()

    # Get number of faults
    if len(args) != 2:
        parser.error("Expecting number of faults and falut types as arguments")
    elif args[0] not in ('reg','mem','ams'):
        parser.error(args[0] + " is not an acceptable fault type")
    elif IsNumber(args[1]) is False:
        parser.error(args[1] + " is not a number")
    else:
        fault_type=args[0]
        num_faults=int(args[1])

    return benchmark, fault_type, num_faults, faults_dir

"""
This function checks if the string can be interpreted as a number
"""
def IsNumber(text):
    try:
        int(text)
        return True
    except ValueError:
        return False

"""
This function checks if a string is a valid AMDAPP benchmark name
We are checking against the list of the benchmarks from m2s
"""
def CheckBenchName(bench):
    if bench not in bench_list:
        return False
    else:
        return True

"""
Function that generates the faults, will create 4 files within the directory
at adjacent bits
"""
def GenFaults(fault_num, cycle_max, fault_type):
    cycle = random.randrange(0, cycle_max)
    cu_id = 0 #random.randrange(0,19)
    if fault_type == 'reg':
        reg_id = random.randrange(0,16383)
        bit = random.randrange(0, 127)
        f1 = open(faults_dir + '/' + str(fault_num), 'w+')
        f1.write ("%d reg %d %d %d\n" % (cycle, cu_id, reg_id, bit))
        f1.close

    elif fault_type == 'mem':        
        byte_num = random.randrange(0, 32767)
        bit = random.randrange(0,7)
        f1 = open(faults_dir + '/' + str(fault_num), 'w+')
        f1.write ("%d mem %d %d %d\n" % (cycle, cu_id, byte_num, bit))
        f1.close

    elif fault_type == 'ams':
        stack_id = random.randrange(0, 31) #MaxWavefromtsPerComputeUnit is 32
        am_id = random.randrange(0, 31) #The number of entries in the stack is 32
        bit = random.randrange(0,63) #WavefrontSize is 64
        f1 = open(faults_dir + '/' + str(fault_num), 'w+')
        f1.write ("%d ams %d %d %d %d\n" % (cycle, cu_id, stack_id, am_id, bit))
        f1.close

    else:
        str_error = 'Unknown fault_type: ' + fault_type
        print str_error
        sys.exit(1)
"""
Main Function
"""


bench,fault_type, num_faults,faults_directory = OptionParsing()
if bench == 'all':
    benchlist = bench_list
else:
    benchlist = [bench]
print benchlist
for bench in benchlist:
    if CheckBenchName(bench) == False:
        pass
    faults_dir = faults_directory + '/' + bench + '_faults'
    if not os.path.exists(faults_dir):
        os.mkdir(faults_dir)
    print "Benchmark:", bench, " - Num of faults: ", num_faults, " - fault dir: " , faults_dir, "fault_type: ", fault_type
    fault_num = 1
    while fault_num <= num_faults:
        if bench == 'MatrixMultiplication':
            GenFaults(fault_num, 1240173, fault_type)
        elif bench == 'MatrixTranspose':
            GenFaults(fault_num, 21452807, fault_type)
        elif bench == 'DwtHaar1D':
            GenFaults(fault_num, 229577, fault_type)
        elif bench == 'ScanLargeArrays':
            GenFaults(fault_num, 7482865, fault_type)
        elif bench == 'BitonicSort':
            GenFaults(fault_num, 130746167, fault_type)
        elif bench == 'DCT':
            GenFaults(fault_num, 4007505, fault_type)
        elif bench == 'PrefixSum':
            GenFaults(fault_num, 21957, fault_type)
        elif bench == 'FastWalshTransform':
            GenFaults(fault_num, 6835898, fault_type)
        elif bench == 'Histogram':
            GenFaults(fault_num, 806711, fault_type)
        elif bench == 'BinarySearch':
            GenFaults(fault_num, 121379, fault_type)
        elif bench == 'Reduction':
            GenFaults(fault_num, 5688353, fault_type)
        elif bench == 'RadixSort':
            GenFaults(fault_num, 1782844, fault_type)
        elif bench == 'URNG':
            GenFaults(fault_num, 19416717, fault_type)
#    elif bench == 'BinomialOption':
#        GenFaults(fault_num, , fault_type)
	fault_num += 1
