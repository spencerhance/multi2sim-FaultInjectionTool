#!/bin/bash
#######################################################
###this is the most up to date script as of may 20th###
#######################################################
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
			--get-results
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


##########################################################
###BRANCH FOR EACH OPTION(--sim/--status/--get-results)###
##########################################################
case "$option" in

	--sim)

	##################
	###CHECK INPUTS###
	##################

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

	#########################
	###GET INPUT FROM USER###
	#########################

	###get benchmark directory###
	read -p "Please enter the benchmark directory on the cluster\
	[~/amdapp-2.5-evg/"$benchmark_name"]" benchmark_dir
	if [[ -z "$benchmark_dir" ]]; then	
		benchmark_dir="~/amdapp-2.5-evg/"$benchmark_name
	        benchmark_dir=$(ssh $ssh_server -p $ssh_port '
		benchmark_dir='$benchmark_dir'
	        cd $benchmark_dir
		pwd
	        ' || exit 1)
	else	 
	        benchmark_dir=$(ssh $ssh_server -p $ssh_port '
	        benchmark_dir='$benchmark_dir'
	        cd "$benchmark_dir"
	        pwd
	        ' || exit 1)
	fi
	
	###get m2s directory###
	read -p "Please enter the path to the m2s binary on the cluster\
	[~/m2s-4.2/bin/m2s]" m2s_path
	if [[ -z "$m2s_path" ]]; then
		m2s_path="~/m2s-4.2/bin/m2s"
	fi
	
	###get benchmark arguments###
	read -p "Please enter any benchmark arguments (-q -e always included)\
        [-q -e]" benchmark_args
	if [[ -z ""$benchmark_args"" ]]; then
		benchmark_args='-q -e'
	else
		benchmark_args=$benchmark_args" -q -e"
	fi

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

        
        #Get the users home directory on the node
        home_dir=$(ssh $ssh_server -p $ssh_port ' echo $HOME
	' || exit 1)

	#get unique folder name
	job_folder=$RANDOM
	
	job_dir=$(ssh -p $ssh_port $ssh_server '
		job_folder='$job_folder'

		mkdir $job_folder
		cd $job_folder
		pwd ' || exit 1)

	echo $job_dir
 
	######################
	###RUN M2S TRAINING### 
	######################
	echo "Running m2s training"
        
        cycle_max=$(ssh $ssh_server -p $ssh_port '
	m2s_path='$m2s_path'
	benchmark_name='$benchmark_name'
	benchmark_kernel='$benchmark_name'"_Kernels.bin"
	benchmark_args='${benchmark_args// /\\ \\}'
	benchmark_dir='$benchmark_dir'
	job_dir='$job_dir'

	cd $job_dir
 
	cat <<- EOF > m2s_training_config.ini
		[ Context 0 ]
		Cwd = $benchmark_dir
		Exe = $benchmark_name
		Args = --load $benchmark_kernel $benchmark_args
		EOF

	srun $m2s_path --evg-sim detailed --ctx-config m2s_training_config.ini \
        2> m2s_training 1>/dev/null 
	temp_cycle_max=$(grep -m2 "Cycles = " m2s_training | tail -n1 | sed "s/[^0-9]//g")
	echo $temp_cycle_max
	' || exit 1)

        #Verify cycle_max is a valid number
        if ! [[ $cycle_max =~ ^[0-9]+$ ]];
          then
              echo "Error occured while running m2s training"
              exit 1
        fi
	
	#Create evg max cycle number for m2s
        evg_max="$(($cycle_max * 2))"

	##########################        
	###GENERATE FAULT FILES###
	##########################
        
        scp -q -P $ssh_port fault_gen.py process_results.py $ssh_server:$job_dir 2>&1 >/dev/null
	echo "Generating faults"
	
        #Generate faults on the server
        ssh $ssh_server -p $ssh_port '
        benchmark_name='$benchmark_name'
        fault_type='$fault_type'
        num_faults='$num_faults'
        cycle_max='$cycle_max'
	job_dir='$job_dir'

	cd $job_dir

        srun fault_gen.py -b "$benchmark_name" "$fault_type" "$num_faults" "$cycle_max" 2>&1>/dev/null
     	' || exit 1     
        

	########################        
	###LAUNCH SIMULATIONS###
	########################

	###submit jobs to slurm###
	echo "Sending jobs"
	output=$(ssh $ssh_server -p $ssh_port '
	num_faults='$num_faults'
	benchmark_name="'$benchmark_name'"
	benchmark_args="'${benchmark_args}'"
	benchmark_dir="'$benchmark_dir'"
	m2s_path='$m2s_path'
	evg_max='$evg_max'
	home_dir="'$home_dir"/"'"
	benchmark_prefix="'$benchmark_name"_"'"
	benchmark_kernel="'$benchmark_name"_Kernels.bin"'"
	job_dir='$job_dir'
	
	cd $job_dir

	touch data.dat
        touch config_data.dat
        mkdir "$benchmark_name""_config_files"

	i=1
	while [[ $i -le $num_faults ]]; do
		echo $job_dir"/"$benchmark_name"_faults/"$i >> data.dat
		echo $job_dir"/"$benchmark_name"_config_files/"$benchmark_name"_config_"$i".ini" >> config_data.dat
		
		cat <<- EOF > $benchmark_name"_config_"$i".ini"
			[ Context 0 ]
			Cwd = $benchmark_dir
			Exe = $benchmark_name
			Args = --load $benchmark_kernel $benchmark_args
			StdOut = $benchmark_prefix$i.out
			EOF
		mv $benchmark_name"_config_"$i".ini" $benchmark_name"_config_files"
		((i++))
	done


	cat <<- EOF > launch.sh
		#!/bin/bash
		num_faults=$num_faults
		benchmark_name="$benchmark_name"
		benchmark_args="${benchmark_args// /\\ \\}"
		benchmark_dir="$benchmark_dir"
		m2s_path="$m2s_path"
		evg_max=$evg_max

		
		PARAMETERS=\$(awk -v line=\${SLURM_ARRAY_TASK_ID} '\''{if (NR==line){ print\$0; };}'\'' ./data.dat)

		CONFIG=\$(awk -v line=\${SLURM_ARRAY_TASK_ID} '\''{if (NR==line){ print\$0; };}'\'' ./config_data.dat)
          
		srun \$m2s_path --evg-sim detailed --evg-max-cycles \$evg_max --evg-faults \$PARAMETERS --evg-debug-faults debug_\$SLURM_ARRAY_TASK_ID --ctx-config \$CONFIG
		EOF

	test=$(sbatch --array=1-$num_faults launch.sh)

	echo $test
	' || exit 1)

	###get slurm job ID###
	slurm_id=$(echo $output | cut -d \  -f 4)          

	####################################
	###LAUNCHING ORGANIZATINAL SCRIPT###
	####################################

	output=$(ssh -p $ssh_port $ssh_server '
	slurm_id='$slurm_id'
	benchmark_name="'$benchmark_name'"
	num_faults='$num_faults'
	home_dir="'$home_dir'"
	benchmark_dir="'$benchmark_dir'"	
	job_dir='$job_dir'

	cd $job_dir

	cat <<- EOF > organize.sh
		#!/bin/bash

		num_faults=$num_faults
		benchmark_name="$benchmark_name"
		slurm_id=$slurm_id
		faults_path=$job_dir/$benchmark_name"_faults/"
		benchmark_dir=$benchmark_dir"/"
		job_dir="$job_dir"
	
		mkdir -p $job_dir"/"$slurm_id"_results"/{1..$num_faults}
		results_path=$job_dir"/"$slurm_id"_results/"
	
		i=1
		while [[ \$i -le \$num_faults ]];
		do
		mv \$faults_path\$i \$results_path\$i
		mv "slurm-"\$slurm_id"_"\$i".out" \$results_path\$i
		mv "debug_"\$i \$results_path\$i
		mv \$benchmark_dir\$benchmark_name"_"\$i".out" \$results_path\$i
		((i++))
	done
		EOF

	sbatch --dependency=afterany:$slurm_id organize.sh
	' || exit 1)

	###get slurm job ID###
	org_slurm_id=$(echo $output | cut -d \  -f 4)

	###############################
	###LAUNCHING DATABASE SCRIPT###
	###############################

	results_dir=$job_dir"/"$slurm_id"_results"

	output=$(ssh -p $ssh_port $ssh_server '
	org_slurm_id='$org_slurm_id'
	slurm_id='$slurm_id'
	results_dir='$results_dir'
	benchmark_name='$benchmark_name'
	job_dir='$job_dir'

	cd $job_dir
	
	cat <<- EOF > process_results.sh
		#!/bin/bash
	
		srun process_results.py $benchmark_name $results_dir $slurm_id
		EOF
		
	sbatch --dependency=afterany:$org_slurm_id process_results.sh
	' || exit 1)

	###get slurm job ID###
	DB_slurm_id=$(echo $output | cut -d \  -f 4)
	
	#######################
	###LAUNCHING CLEANUP###
	#######################

#	ssh -p $ssh_port $ssh_server '
#	slurm_id='$slurm_id'
#	DB_slurm_id='$DB_slurm_id'
#	org_slurm_id='$org_slurm_id'
#	benchmark_name='$benchmark_name'

#	cat <<- EOF > $slurm_id"_clean.sh"
#		#!/bin/bash
		
#		srun rm -r process_results.py process_results.sh slurm-$DB_slurm_id".out" slurm-$org_slurm_id".out" organize.sh config_data.dat $benchmark_name"_config_files"
#		EOF
	
#	sbatch --dependency=afterany:$DB_slurm_id $slurm_id"_clean.sh" 2>&1>/dev/null
#	' || exit 1

	echo "Jobs sent"

	###########################
	###CREATE TEMPORARY FILE###
	###########################
	;;


	--status)

		while read line; do
			temp+=($line)
		done < vars.dat
	;;
	
	--get-results)
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
              
	#Ending case
	;;
    
	*)
	echo "$option"" is an invalid selection"
	syntax
	exit 1
	;;
esac
