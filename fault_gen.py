#!/usr/bin/env python

import sys
import os
from optparse import OptionParser
import random
from subprocess import call

def optionParsing():
    """
    Parses the program input
    """
    usage = "usage: %prog [options] <fault_type> <num_faults> <max_cycles>"
    parser = OptionParser(usage=usage)
    parser.add_option("-b", "--bench-name", dest="benchmark",
                      help="Benchmark to generate faults for", metavar="BENCHMARK_NAME")
    parser.add_option("-f", "--faults-dir", dest="fault_dir",
                      help="Directory where the faults will be located", metavar="FAULT_DIR")
    parser.add_option("-c", "--max-cu", dest="max_cu",
                      help="Specify max compute unit", metavar="MAX_CU")
    (options, args) = parser.parse_args()

    # Get benchmark name
    if options.benchmark:
        benchmark_name = options.benchmark
        if checkBenchName(benchmark_name) is False and benchmark_name != 'amd':
            print benchmark_name, " is not in the bench list"
            parser.error("Wrong benchmark name")
    else:
        benchmark_name = "amd"
        
    # Get directory for faults
    if options.fault_dir:
        fault_dir = options.fault_dir 
        if os.path.isdir(options.fault_dir) is False:
            parser.error(fault_dir + " is not a directory") 
    else:
        fault_dir = os.getcwd()
    fault_dir = fault_dir + '/' + benchmark_name + '_faults'

    #Get the max compute unit
    if options.max_cu:
        max_cu = options.max_cu
    else:
        max_cu = 19

    # Get number of faults and verify input
    if len(args) != 3:
        parser.error("Expecting number of faults and fault types as arguments")
    elif isNumber(args[1]) is False:
        parser.error(args[1] + " is not a number")
    elif isNumber(args[2]) is False:
        parser.error(args[2] + " is not a number")
    else:
        fault_type=args[0]
        num_faults=int(args[1])
        cycle_max=int(args[2])

    return benchmark_name, fault_type, num_faults, cycle_max, fault_dir, max_cu


def isNumber(text):
    """
    Checks if string can be converted to a number
    """
    try:
        int(text)
        return True
    except ValueError:
        return False

def checkBenchName(benchmark_name):
    """
    This function checks if a string is a valid AMDAPP benchmark name
    We are checking against the list of the benchmarks from m2s
    """
    if benchmark_name not in amd_bench_list:
        return False
    else:
        return True

def GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu):
    """
    Function that generates the faults
    """
    cycle = random.randint(1, cycle_max)
    cu_id = random.randint(0, max_cu) 
    if fault_type == 'reg':
        reg_id = random.randint(0,16383)
        bit = random.randint(0, 127)
        f1 = open(fault_dir + '/' + str(fault_num), 'w+')
        f1.write ("%d reg %d %d %d\n" % (cycle, cu_id, reg_id, bit))
        f1.close

    elif fault_type == 'mem':        
        byte_num = random.randint(0, 32767)
        bit = random.randint(0,7)
        f1 = open(fault_dir + '/' + str(fault_num), 'w+')
        f1.write ("%d mem %d %d %d\n" % (cycle, cu_id, byte_num, bit))
        f1.close

    elif fault_type == 'ams':
        stack_id = random.randint(0, 31) #MaxWavefromtsPerComputeUnit is 32
        am_id = random.randint(0, 31) #The number of entries in the stack is 32
        bit = random.randint(0,63) #WavefrontSize is 64
        f1 = open(fault_dir + '/' + str(fault_num), 'w+')
        f1.write ("%d ams %d %d %d %d\n" % (cycle, cu_id, stack_id, am_id, bit))
        f1.close

    else:
        str_error = 'Unknown fault_type: ' + fault_type
        print str_error
        sys.exit(1)

    
def main(): 
    """
    Main Function
    """
    #List of AMDAPP benchmarks
    global amd_bench_list
    amd_bench_list = ('BinarySearch',
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
    
    benchmark_name, fault_type, num_faults,cycle_max, fault_dir, max_cu \
            = optionParsing()
    if benchmark_name == 'amd':
        bench_list = amd_bench_list
    else:
        bench_list = [benchmark_name]
    for bench in bench_list: 
        if not os.path.exists(fault_dir):
            os.mkdir(fault_dir)
        fault_num = 1
        while fault_num < num_faults + 1:
            if bench == 'MatrixMultiplication':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'MatrixTranspose':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'DwtHaar1D':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'ScanLargeArrays':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'BitonicSort':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'DCT':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'PrefixSum':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'FastWalshTransform':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'Histogram':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'BinarySearch':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'Reduction':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'RadixSort':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            elif bench == 'URNG':
                GenFaults(fault_num, cycle_max, fault_type, fault_dir, max_cu)
            fault_num += 1
    

if __name__ == '__main__':
    main()





