#!/bin/bash
#######################################################
###this is the most up to date script as of may 21st###
#######################################################
set -o errexit

function syntax()
{
	cat <<- ENDOFTEXT
		Syntax: $0 <OPTION>

		OPTIONS:
			--sim <ssh_server> <benchmark_name> <fault_type> <num_faults> <num_cu> <ssh_port>
			        runs simulation of benchmark_name with num_faults injected into memory region fault_type
			        ssh_server: user@ip_of_server
			        benchmark_name: name of benchmark to run
			        fault_type: region to inject faults in (mem, reg, or ams)
			        num_faults: number of faults to inject
			        ssh_port: default is 22
	
			--status
			        returns status of running simulations. If simulation is complete, results are returned to cwd on localhost
		
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

	if [ $# -lt 6 ];
	then
		syntax	
		exit 1
	fi
        
        if [[ -z "$7" ]];
	then
		ssh_port=22
	else
		ssh_port=$7
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
	        
        if [[ ( $6 =~ ^[0-9]+$ ) && ( $6 -ge 0 ) && ( $6 -le 19 ) ]];
          then
                num_cu=$6
          else
                echo "ERROR: invalid number of compute units" >&2;
                exit 1
        fi
       
	#########################
	###GET INPUT FROM USER###
	#########################


        #Get the users home directory on the node
        home_dir=$(ssh $ssh_server -p $ssh_port ' echo $HOME
	' || exit 1)

	###get benchmark directory###
	read -p "Please enter the benchmark directory on the server\
	[$home_dir/amdapp-2.5-evg/"$benchmark_name"]" benchmark_dir
	if [[ -z "$benchmark_dir" ]]; then	
		benchmark_dir=$home_dir"/amdapp-2.5-evg/"$benchmark_name
	fi
	
	###get m2s directory###
	read -p "Please enter the path to the m2s binary on the server\
	[$home_dir/m2s-4.2/bin/m2s]" m2s_path
	if [[ -z "$m2s_path" ]]; then
		m2s_path=$home_dir"/m2s-4.2/bin/m2s"
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
	if [ ! -d "'$benchmark_dir'" ];
        then
            echo "ERROR: ""'$benchmark_dir'"" does not exist"
            exit 1
	fi

	if [ ! -f "'$m2s_path'" ];
	then
            echo "ERROR: ""'$m2s_path'"" does not exist"
            exit 1
	fi
	' || exit 1

	#get unique folder name
	job_folder=$RANDOM
	
	job_dir=$(ssh -p $ssh_port $ssh_server '
		job_folder='$job_folder'

		mkdir $job_folder
		cd $job_folder
		pwd ' || exit 1)

	######################
	###RUN M2S TRAINING### 
	######################
	echo "Running m2s training"
        
        cycle_max=$(ssh $ssh_server -p $ssh_port '
	cd '$job_dir'
 
	cat <<- EOF > m2s_training_config.ini
		[ Context 0 ]
		Cwd = '$benchmark_dir'
		Exe = '$benchmark_name'
		Args = --load '$benchmark_name'_Kernels.bin '$benchmark_args'
		EOF

	srun '$m2s_path' --evg-sim detailed --ctx-config m2s_training_config.ini \
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

	############################################        
	###GENERATE FAULTS AND LAUNCH SIMULATIONS###
	############################################
       
	scp -q -P $ssh_port fault_gen.py process_results.py $ssh_server:$job_dir 2>&1 >/dev/null

	###submit jobs to slurm###
	echo "Generating faults and sending jobs"

	output=$(ssh $ssh_server -p $ssh_port '	
	cd '$job_dir'
	
        srun fault_gen.py -b '$benchmark_name' -c '$num_cu' '$fault_type' '$num_faults' '$cycle_max' 2>&1>/dev/null

	touch data.dat
        touch config_data.dat
        mkdir '$benchmark_name'"_config_files"

	i=1
	while [[ $i -le '$num_faults' ]]; do
		echo '$job_dir'"/"'$benchmark_name'"_faults/"$i >> data.dat
		echo '$job_dir'"/"'$benchmark_name'"_config_files/"'$benchmark_name'"_config_"$i".ini" >> config_data.dat
		
		cat <<- EOF > '$benchmark_name'"_config_"$i".ini"
			[ Context 0 ]
			Cwd = '$benchmark_dir'
			Exe = '$benchmark_name'
			Args = --load '$benchmark_name'_Kernels.bin '$benchmark_args'
			StdOut = '$benchmark_name'_$i.out
			EOF
		mv '$benchmark_name'"_config_"$i".ini" '$benchmark_name'"_config_files"
		((i++))
	done


	cat <<- EOF > launch.sh
		#!/bin/bash
		num_faults='$num_faults'
		benchmark_name="'$benchmark_name'"
		benchmark_args="'$benchmark_args'"
		benchmark_dir="'$benchmark_dir'"
		m2s_path="'$m2s_path'"
		evg_max='$evg_max'

		
		PARAMETERS=\$(awk -v line=\${SLURM_ARRAY_TASK_ID} '\''{if (NR==line){ print\$0; };}'\'' ./data.dat)

		CONFIG=\$(awk -v line=\${SLURM_ARRAY_TASK_ID} '\''{if (NR==line){ print\$0; };}'\'' ./config_data.dat)
          
		\$m2s_path --evg-sim detailed --evg-max-cycles \$evg_max --evg-faults \$PARAMETERS --evg-debug-faults debug_\$SLURM_ARRAY_TASK_ID --ctx-config \$CONFIG
		EOF

	test=$(sbatch --array=1-'$num_faults' launch.sh)

	echo $test
	' || exit 1)

	###get slurm job ID###
	slurm_id=$(echo $output | cut -d \  -f 4)          

	###############################
	###LAUNCHING DATABASE SCRIPT###
	###############################
	results_dir=$job_dir"/"$slurm_id"_results"

	ssh -p $ssh_port $ssh_server '
	cd '$job_dir'

	cat <<- EOF > organize.sh
		#!/bin/bash

		num_faults='$num_faults'
		benchmark_name="'$benchmark_name'"
		slurm_id='$slurm_id'
		faults_path='$job_dir'/'$benchmark_name'_faults/
		benchmark_dir='$benchmark_dir'/
		job_dir='$job_dir'
	
		mkdir -p '$job_dir'"/"'$slurm_id'"_results"/{1..'$num_faults'}
		results_path='$job_dir'"/"'$slurm_id'"_results/"
	
		i=1
		while [[ \$i -le \$num_faults ]];
		do
		mv \$faults_path\$i \$results_path\$i
		mv "slurm-"\$slurm_id"_"\$i".out" \$results_path\$i
		mv "debug_"\$i \$results_path\$i
		mv \$benchmark_dir\$benchmark_name"_"\$i".out" \$results_path\$i
		((i++))
		done

		./process_results.py '$benchmark_name' '$results_dir' '$slurm_id'

		touch DONE
		EOF

	sbatch --dependency=afterany:'$slurm_id' organize.sh 2>&1>/dev/null
	' || exit 1

	echo "Jobs sent"
	
	###########################
	###CREATE TEMPORARY FILE###
	###########################
	cat <<- EOF >> var.tmp
		$job_dir $slurm_id $benchmark_name $ssh_server $ssh_port
		EOF
	;;


	--status)

		while read line; do
			temp+=($line)
		done < var.tmp

		lines=$((${#temp[@]} / 5))
		OS=$(uname -s)
		i=0
		while [[ $i -lt $lines ]]; do
			status=$(ssh ${temp[3+$i*5]} -p ${temp[4+$i*5]} '
				if [ -e "'${temp[$i*5]}'/DONE" ]; then
					echo "Job Finished"
				else
					squeue -j '${temp[1+$i*5]}'
				fi ')
			cat <<- EOF
				Slurm_Job_ID=${temp[1+$i*5]}
				Benchmark_name=${temp[2+$i*5]}
				Status=$status				
				EOF
			if [ "$status" == "Job Finished" ]; then
				echo "Copying back results..."
				scp -q -r -P ${temp[4+$i*5]} ${temp[3+$i*5]}:${temp[$i*5]}/${temp[1+$i*5]}_results ./
				scp -q -r -P ${temp[4+$i*5]} ${temp[3+$i*5]}:${temp[$i*5]}/${temp[1+$i*5]}_${temp[2+$i*5]}.db ./
				ssh ${temp[3+$i*5]} -p ${temp[4+$i*5]} '
					rm -r '${temp[$i*5]}'
				'
			fi

			i+=1

			if [ "$status" == "Job Finished" ]; then 
				sed -i -e "$i"d var.tmp

				if [ "$OS" == "Darwin" ]; then
					rm var.tmp-e
				fi
			fi
		done


	;;
	
	*)
	echo "$option"" is an invalid selection"
	syntax
	exit 1
	;;
esac
