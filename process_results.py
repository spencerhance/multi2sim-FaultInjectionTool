#!/usr/bin/env python

import sys
import os
import re
import sqlite3
import ConfigParser
import fileinput

def initDb(db_name):
    """
    Adds Tables to sql database
    """
    conn = sqlite3.connect(db_name + '.db')
    c = conn.cursor()
    
    c.execute('CREATE TABLE IF NOT EXISTS '\
              'RegFaults(ID INTEGER PRIMARY KEY, FaultNum INTEGER, '\
              'Type TEXT, Bench TEXT, Cycle INTEGER, CuID INTEGER, '\
              'RegID INTEGER, Bit INTEGER,Outcome TEXT, '\
              'TotalCycles INTEGER, GPUCycles INTEGER, '\
              'Effect TEXT, WG INTEGER, WF INTEGER, '\
              'WI INTEGER, LoReg INTEGER)')
    c.execute('CREATE TABLE IF NOT EXISTS '\
              'MemFaults(ID INTEGER PRIMARY KEY, FaultNum INTEGER, '\
              'Type TEXT, Bench TEXT, Cycle INTEGER, CuID INTEGER, '\
              'ByteID INTEGER, Bit INTEGER, Outcome TEXT, '\
              'TotalCycles INTEGER, GPUCycles INTEGER, Effect TEXT, '\
              'WG INTEGER, WF INTEGER, WI INTEGER, Byte INTEGER)')
    c.execute('CREATE TABLE IF NOT EXISTS '\
              'AmsFaults(ID INTEGER PRIMARY KEY, FaultNum INTEGER, '\
              'Type TEXT, Bench TEXT, Cycle INTEGER, CuID INTEGER,  StackID INTEGER, '\
              'MaskID INTEGER, Bit INTEGER, Outcome TEXT, TotalCycles INTEGER, '\
              'GPUCycles INTEGER, Effect TEXT)')

    return c, conn;

def processSimOutput(sim_output_path, benchmark_out_path):
    """
    Processes the slurm m2s output and returns associated
    variables
    """
    sim_output_config = ConfigParser.RawConfigParser()
    for line in fileinput.input(sim_output_path, inplace=True):
        print(line.replace("warning", ";warning")).rstrip('\n')
    try:
        sim_output_config.read(sim_output_path)
        sim_end = sim_output_config.get(' General ', 'SimEnd')
        cycle_total = sim_output_config.getint(' General ', 'Cycles')
        cycle_gpu = sim_output_config.getint(' Evergreen ', 'Cycles')
        ipc_gpu = sim_output_config.getfloat(' Evergreen ', 'IPC')
    except:
        sim_end, cycle_total, cycle_gpu, ipc_gpu = 'null', 0, 0, 0

    if sim_end == 'ContextsFinished':
        outcome = processBenchmarkOutput(benchmark_out_path)
    #If fault was not injected
    elif sim_end == 'EvergreenNoFaults':
        outcome = 'not_injected'
    #If simulation reached max cycles    
    elif sim_end == 'EvergreenMaxCycles':
        outcome = 'cycle_timeout'
    else:
        outcome = 'Unknown'
    
    return sim_end, outcome, cycle_total, cycle_gpu, ipc_gpu

def processBenchmarkOutput(benchmark_out_path):
    """
    Processes the stdout generated by the benchmark
    """
    with open(benchmark_out_path) as benchmark_output:
        for line in benchmark_output:
            if line == 'Passed!\n':
                outcome = 'Passed'
                break
            elif line == 'Failed\n':
                outcome = 'Failed'
                break
            else:
                outcome = 'Unknown'
    return outcome

def processDebugOutput(debug_output, fault_type):
    """
    Processes the m2s debug output and returns associated
    variables
    """
    effect = re.search('.*effect=.(\w+)', debug_output).group(1)
    if effect == 'error':
        if fault_type == 'reg':
            data=re.search(
                '.*bit=([\d]+).*wg=([\d]+).*wf=([\d]+).*wi=([\d]+).*lo_reg=([\d]+)', 
                debug_output)
            if data:
                bit, wg, wf, wi, lo_reg = int(data.group(1)), int(data.group(2)),\
                        int(data.group(3)), int(data.group(4)), int(data.group(5))
                byte = -1
        elif fault_type == 'mem':
            data=re.search('.*byte=([\d]+).*bit=([\d]+).*wg=([\d]+)',
                    debug_output)
            if data:
                byte, bit, wg = int(data.group(1)), int(data.group(2)), int(data.group(3))
                wf, wi, lo_reg = -1, -1, -1
        elif fault_type == 'ams':
            data=re.search(
                '.*bit=([\d]+).*wg=([\d]+).*wf=([\d]+).*wi=([\d]+)', 
                debug_output)
            if data:
                bit, wg, wf, wi = int(data.group(1)), int(data.group(2)),\
                        int(data.group(3)), int(data.group(4))
                byte, lo_reg = -1, -1
    else:
        bit, wg, wf, wi, lo_reg, byte = -1, -1, -1, -1, -1, -1
    return bit, effect, wg, wf, wi, lo_reg, byte

    
def main():
    """
    MAIN FUNCTION
    """
    #Parse input
    benchmark_name = str(sys.argv[1])
    results_dir = str(sys.argv[2]) 
    slurm_id = sys.argv[3]
    
    #Initialize the database and return sqlite objects
    db_name = str(slurm_id) + '_' + benchmark_name 
    c, conn = initDb(db_name)
    
    #Determine the number of fault folders to parse
    if os.path.isdir(results_dir) == False:
        print 'Results directory does not exist'
        return 1;
    fault_file_list = os.listdir(results_dir) 
    num_faults = max([int(i) for i in fault_file_list])
    
    for i in range(1, num_faults + 1):
        fault_id = str(i)
        current_dir = results_dir + '/' + fault_id
        
        #Get variables from sim output (SLURM) and bench output
        sim_output_path = current_dir + '/' + 'slurm-' + slurm_id \
                + '_' + fault_id + '.out'
        benchmark_out_path = current_dir + '/' + benchmark_name \
                + '_' + fault_id + '.out'
        sim_end, outcome, cycle_total, cycle_gpu, ipc_gpu = \
                processSimOutput(sim_output_path, benchmark_out_path)

        #Get variables from fault files (fault_gen)
        fault_info = open(current_dir + '/' + fault_id).read().split()
        fault_cycle, fault_type, fault_cu = \
                int(fault_info[0]), fault_info[1], int(fault_info[2])
                
        #Open debug output (M2S)
        debug_output = open(current_dir + '/' + 'debug_' + fault_id).read()
        
        if fault_type == 'reg':
            fault_reg, fault_bit = \
                    int(fault_info[3]), int(fault_info[4])
            #Process debug output
            bit, effect, wg, wf, wi, lo_reg, byte = \
                    processDebugOutput(debug_output, fault_type)
            #Add data to table
	    c.execute('INSERT OR IGNORE INTO RegFaults '\
                      'VALUES(NULL, %d, \'%s\', \'%s\', %d, %d, %d, %d, \'%s\', '\
                      '%d, %d, \'%s\', %d, %d, %d, %d);'
                      % (i, fault_type, benchmark_name, fault_cycle,
                         fault_cu, fault_reg,  fault_bit, outcome, cycle_total, 
                         cycle_gpu, effect, wg, wf, wi, lo_reg))  
        
        elif fault_type == 'mem':
            fault_byte, fault_bit = \
                int(fault_info[3]), int(fault_info[4])
            #Process debug output
            bit, effect, wg, wf, wi, lo_reg, byte = \
                    processDebugOutput(debug_output, fault_type)
            #Add data to table
            c.execute('INSERT OR IGNORE INTO MemFaults '\
                      'VALUES (NULL, %d, \'%s\', \'%s\', %d, %d, %d, %d, \'%s\', %d, '\
                      '%d, \'%s\', %d, %d, %d, %d);'
                      % (i, fault_type, benchmark_name, fault_cycle, 
                         fault_cu, fault_byte, fault_bit, outcome, cycle_total, 
                         cycle_gpu, effect, wg, wf, wi, byte))
            
        elif fault_type == 'ams':
            fault_stack, fault_mask, fault_bit = \
                    int(fault_info[3]), int(fault_info[4]), \
                    int(fault_info[5])
            #Process debug output
            bit, effect, wg, wf, wi, lo_reg, byte = \
                    processDebugOutput(debug_output, fault_type)
            #Add data to table
            c.execute('INSERT OR IGNORE INTO AmsFaults '\
                      'VALUES(NULL, %d, \'%s\', \'%s\', %d, %d, %d, %d, %d, \'%s\', %d, '\
                      '%d, \'%s\');'
                      % (i, fault_type, benchmark_name, fault_cycle, 
                         fault_cu, fault_stack, fault_mask, fault_bit, outcome, cycle_total, 
                         cycle_gpu, effect))
        conn.commit()
          
    
if __name__ == '__main__':
        main()

