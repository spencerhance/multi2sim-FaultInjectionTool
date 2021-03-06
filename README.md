# m2s Fault Injection Tool

## Introduction

This fault injection tool is meant to be used as a tool to launch
massive Multi2Sim fault injection simulations on a cluster.  Multi2Sim 
is a heterogenous system simulator available at 
https://www.multi2sim.org. The tool is currently working with 
multi2sim-4.2 Evergreen architecture and SLURM as the cluster 
management tool.

## Modules

The uncompressed folder includes 3 files, fault_tool.sh, 
process_results.py, and fault_gen.py.  The fault_tool bash script is
the central script where everything is launched. fault_gen.py is an
internal module which will generate the m2s fault files needed for m2s
fault injection.  process_results.py is an internal module which 
processes the results and creates a sqlite3 database with important 
information from the simulations.

## Usage

To run the tool, the fault_tool.sh bash script must be run from the 
command line
The syntax is as follows:

```
--sim <ssh_server> <benchmark_name> <fault_type> <num_faults> <num_cu> <ssh_port>
	runs simulation of benchmark_name with num_faults injected 
	into memory region fault_type

		ssh_server: user@ip_of_cluster
		benchmark_name: name of benchmark to run
		fault_type: region to inject faults in (mem, reg, or ams)
		num_faults: number of faults to inject
		num_cu: number of compute units, max is 19
		ssh_port (OPTIONAL): default is 22

--status 
	returns status of running simulations
```

      	
In order to launch the simulations, the --sim command must be used
with its requisite input.  All inputs are required except the port
number.  If no port number is specified it will default to 22.
While the program is running you will be prompted 
for the m2s and benchmark directories on the cluster as well as any
benchmark arguments.  
To view the status of your current simulations, run the --status
command.  This will display the information and queue for each
simulation you have launched.  If the simulations has completed,
"Job Finished" will be printed and the results data will be copied
back to the cwd on your local machine.  Additionally, it will delete all 
temporary files created for that simulation from the cluster.


## Results

Once you have recieved the results, you will have a copy
of the results directory as well as a compressed results folder on
your local machine.  The results folder, once extracted, contains
a subdirectory for each fault.  In those fault directories will be
the fault file passed to Multi2Sim, the debug file outputted by
Multi2Sim, the benchmark output, and the simulation output from
Multi2Sim.  These are provided mainly for debugging purposes as the
database provides the most useful results.  The sqlite3 database will
be named with following convention: <job_id>_<benchmark_name>.db

To view your results database on your machine, navigate to the 
fault_injection_tool folder in terminal and run this command:

`$ sqlite3 <path_to_database> -column`

This will open up a sqlite3 terminal.  Then type:

`sqlite> .headers on`

This will turn on headers to make viewing the data easier.  
The next step is to open the table.  This is done with the 
following command:

`sqlite> SELECT * FROM <table_name>;`

The table_name will be either "MemFaults,"RegFaults," or "AmsFaults," 
depending on the simulation you suggested.  This will display all 
of the fault injection data in your terminal window


## Launching Multiple Simulations

Launching multiple simulations is possible, however too many launches
in a row triggers a brute force protection mechanism that can freeze
your jobs.  The same issue can occur when using the --status flag.
We recommend launching no more than two simulation batches in a row
and waiting 15 seconds between running the --status option.


## Dependencies

* Cluster running SLURM
* Keyless access to cluster
* AMD OpenCl SDK 2.5 benchmarks for evergreen on the cluster
* multi2sim-4.2 built on the cluster
* sqlite3 on the node
* sqlite3 on your local machine to view results
* bash 4.3.11 or newer on the cluster 
* Python 2.7 libraries
  * sys
  * os
  * re
  * sqlite3 
  * ConfigParser
  * fileinput
  * OptionParser






















