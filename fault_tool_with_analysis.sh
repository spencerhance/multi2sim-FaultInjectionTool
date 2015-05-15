#!/usr/local/bin/bash
###change this, this is only for my mac###

set -o errexit

function syntax()
{
	cat <<- ENDOFTEXT
		Syntax: $0 <OPTION>

		OPTIONS:
			--sim <ssh_server> <benchmark_name> <fault_type> <num_faults> <ssh_port>
			        runs simulation of benchmark_name with num_faults injected into memory region fault_type
			        ssh_server: user@ip_of_cluster
			        benchmark_name: name of benchmark to run
			        fault_type: region to inject faults in (mem, reg, or ams)
			        num_faults: number of faults to inject
			        ssh_port: default is 22
	
			--status <ssh_server>
			        returns status of running simulations
			        ssh_server: user@ip_of_cluster
			--get_results
			        pulls results from server to client
		
ENDOFTEXT
}

if [ $# -lt 1 ];
then
	echo "ERROR: insufficient number of arguments"
	syntax
	exit 1
fi

if [ $1 == "-h" ];
then
	syntax
	exit 0
fi

###list of valid benchmarks###
declare -a bench_list=('BinarySearch' \
                       'BinomialOption' \
                       'BitonicSort' \
                       'BlackScholes' \
                       'BoxFilter' \
                       'DCT' \
                       'DwtHaar1D' \
                       'FastWalshTransform' \
                       'FloydWarshall' \
                       'Histogram' \
                       'MatrixMultiplication' \
                       'MatrixTranspose' \
                       'PrefixSum' \
                       'RadixSort' \
                       'RecursiveGaussian' \
                       'Reduction' \
                       'ScanLargeArrays' \
                       'SobelFilter' \
                       'URNG')

#store 1st arg
option=$1


#######################################################
#branch for each option (--sim/--status/--get_results)#
#######################################################
case "$option" in
	--sim)

	###check all inputs for errors###
	###store vlaues if valid###
	if [ $# -lt 5 ];
	then
		syntax	
		exit 1
	fi

	if [[ -z "$ssh_port" ]];
	then
		ssh_port=22
	else
		ssh_port=$6
	fi

	ssh_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$2" -p "$ssh_port" echo ok)
	if [ $ssh_status == "ok" ];
	then
		ssh_server=$2
	fi

	if [[ " ${bench_list[@]} " =~ " $3 " ]];
	then
		benchmark_name=$3
	else
		echo "ERROR: invalid benchmark name" >&2;
		echo "Enter one of the following:"
		for i in ${bench_list[@]}; do
			echo $i
		done

		exit 1
	fi

	if [ "$4" == "mem" -o "$4" == "reg" -o "$4" == "ams" ];
	then
      		fault_type=$4
  	else
      		echo "ERROR: invalid fault type" >&2;
      		exit 1
	fi

	if [[ ( $5 =~ ^[0-9]+$ ) && ( $5 -gt 0 ) ]];
  	then
      		num_faults=$5  
  	else
     		 echo "ERROR: invalid number of faults, must be an integer greater than 0" >&2;
      		exit 1
	fi

	###get <benchmark_dir> <m2s_dir> and <benchmark_args>###
	read -p "Please enter the benchmark directory on the cluster\
	[~/amdapp-2.5-evg/"$benchmark_name"]" benchmark_dir
	while [[ -z "$benchmark_dir" ]];
	do
		benchmark_dir="~/amdapp-2.5-evg/""$benchmark_name"
	done

	read -p "Please enter the path to the m2s binary on the cluster\
	[~/m2s-4.2/bin/m2s]" m2s_path
	while [[ -z "$m2s_path" ]];
        do
		m2s_path="~/m2s-4.2/bin/m2s"
	done

	read -p "Please enter any benchmark arguments\
        [-q -e]" benchmark_args
	while [[ -z ""$benchmark_args"" ]];
	do
		benchmark_args='-q -e'
	done

	###check for valid paths###
	ssh $ssh_server -p "$ssh_port" '
	benchmark_dir='$benchmark_dir'
	m2s_path='$m2s_path'
	if [ ! -d "$benchmark_dir" ];
        then
            echo "ERROR: ""$benchmark_dir"" does not exist"
            exit 1
	fi

	if [ ! -f "$m2s_path" ];
	then
            echo "ERROR: ""$m2s_path"" does not exist"
            exit 1
	fi
	' || exit 1

	home_dir=$(ssh $ssh_server -p $ssh_port ' echo $HOME
	' || exit 1)

	
	echo "Running m2s training"
	cycle_max=$(ssh $ssh_server -p $ssh_port '
	m2s_path='$m2s_path'
	benchmark_name='$benchmark_name'
	benchmark_args='${benchmark_args// /\\ \\}'
	benchmark_dir='$benchmark_dir'
	srun $m2s_path --evg-sim detailed "$benchmark_dir"/"$benchmark_name" \
	--load "$benchmark_name""_Kernels.bin" $benchmark_args \
	> m2s_training 2>&1 >/dev/null 
	temp_cycle_max=$(grep -m2 "Cycles = " m2s_training | tail -n1 | sed "s/[^0-9]//g")
	echo $temp_cycle_max
	' || exit 1)

	###generate the fault files###
	echo "Generating faults"
	./fault_gen.py -b "$benchmark_name" "$fault_type" "$num_faults" "$cycle_max" 2>&1>/dev/null
   
	###copy all fault files to server### 
	tar czf $benchmark_name"_faults"".tar.gz" "$benchmark_name""_faults" >/dev/null
	scp -q "$benchmark_name""_faults"".tar.gz" "$ssh_server":~/ 2>&1 >/dev/null
      
	###create file with paths to all fault files###
	touch data.dat
	i=1
	while [[ $i -le $num_faults ]]; 
	do
		echo "$home_dir""/""$benchmark_name""_faults""/$[i]" >> data.dat
		((i++))
	done

	###create slurm launch script###
	touch launch.sh
	echo "#!/bin/bash" >> launch.sh
	echo num_faults="$num_faults" >> launch.sh
	echo benchmark_name="$benchmark_name" >> launch.sh
	echo benchmark_args="${benchmark_args// /\\ \\}" >> launch.sh
	echo benchmark_dir="$benchmark_dir" >> launch.sh
	echo m2s_path="$m2s_path" >> launch.sh

	echo 'PARAMETERS=$(awk -v line=${SLURM_ARRAY_TASK_ID} '\''{if (NR==line){ print$0; };}'\'' ./data.dat)' >> launch.sh

	echo 'srun $m2s_path --evg-sim detailed --evg-faults $PARAMETERS --evg-debug-faults debug_$SLURM_ARRAY_TASK_ID "$benchmark_dir"/"$benchmark_name" --load "$benchmark_name"_Kernels.bin ''$benchmark_args''' >> launch.sh

	###copy launch script and data to server###
	scp -q -P $ssh_port data.dat launch.sh $ssh_server:~/ 2>&1 >/dev/null

	###submit jobs to slurm###
	echo "Sending jobs"
	output=$(ssh $ssh_server -p $ssh_port '
	num_faults='$num_faults'
	benchmark_name='$benchmark_name'
	benchmark_args='${benchmark_args// /\\ \\}'
	benchmark_dir='$benchmark_dir'
	m2s_path='$m2s_path'
	tar xvzf $benchmark_name"_faults"".tar.gz" >/dev/null
	fault_dir_cluster=$"$benchmark_name""_faults"
      
	test=$(sbatch --array=1-$num_faults launch.sh)
	rm "$benchmark_name""_faults"".tar.gz"
	rm m2s_training
	echo $test
	' || exit 1)

	echo "Jobs sent"
	###get slurm job ID###
	slurm_id=$(echo $output | cut -d \  -f 4)

	###Clean up used scripts###
	rm launch.sh
	rm data.dat
	rm "$benchmark_name""_faults"".tar.gz"
	rm -r "$benchmark_name""_faults"

	###make temporary file to store variables###
	touch vars.dat
	echo "$slurm_id $ssh_server $ssh_port" >> vars.dat
	;;
	###end case###

	--status)
		while read line; do
			temp+=($line)
		done < vars.dat
		
		for i in ${temp[@]}; do
					
	#	ssh ${temp[1]} -p ${temp[2]} '
	#		job_id='${temp[0]}'
	#		squeue -j $job_id 
	#		' || exit 1 	
	;;
	
	--get_results)
	read -p "Enter Slurm Job ID: " slurm_id
	while [[ -z "$slurm_id" ]];
	do
		read -p "Enter Slurm Job ID: " slurm_id
	done
      
	if [[ ( ! $slurm_id =~ ^[0-9]+$ ) || ( ! $slurm_id -gt 0 ) ]];
        then
		echo "ERROR: invalid slurm_ID" >&2;
		exit 1
	fi

	ssh $ssh_server -p $ssh_port '
	num_faults='$num_faults'
	benchmark_name='$benchmark_name'
	slurm_id='$slurm_id'
	faults_path='~/'"$benchmark_name""_faults/"

	mkdir -p results/'{1..$num_faults}'
	results_path='~/'"results/"
      
	i=1
	while [[ $i -le $num_faults ]];
	do
		mv "$faults_path""$i" "$results_path""$i" 
		mv "slurm-""$slurm_id""_""$i"".out" "$results_path""$i" 
		mv "debug_""$i" "$results_path""$i" 
		((i++))
	done
      
	rm -r "$faults_path"
	rm launch.sh
	rm data.dat
	' || exit 1

	#PYTHON ANALYSIS GOES HERE
	#tar results dir
	#scp results dir to home machine
	#./process_results.py $fault_dir $fault_type

      	echo "Analysis complete"

	#Ending case
	;;
    
	*)
	echo "$option"" is an invalid selection"
	syntax
	exit 1
	;;
esac
