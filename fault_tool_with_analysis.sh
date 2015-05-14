#!/bin/bash

set -o errexit

function syntax()
{
     echo  "Syntax: $0 <ssh_server> <benchmark_name> <fault type> <num_faults>"
}

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

#Checking for basic input
if [ $# -lt 4 ];
  then
      echo "Requires 4 arguments"
      syntax
      exit 1
fi

if [ $1 == "-h" ];
  then
      syntax
      exit 0
fi


read -p "Please enter the port number of your ssh server\
  [22]" ssh_port
while [[ -z "$ssh_port" ]];
  do
      ssh_port=22
done

ssh_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$1" -p "$ssh_port" echo ok)
if [ $ssh_status == "ok" ];
  then
      ssh_server=$1
fi

if [[ " ${bench_list[@]} " =~ " $2 " ]];
  then
      benchmark_name=$2
  else
      echo "ERROR: invalid benchmark name" >&2;
      exit 1
fi

if [ "$3" == "mem" -o "$3" == "reg" -o "$3" == "ams" ];
  then
      fault_type=$3
  else
      echo "ERROR: invalid fault type" >&2;
      exit 1
fi

if [[ ( $4 =~ ^[0-9]+$ ) && ( $4 -gt 0 ) ]];
  then
      num_faults=$4  
  else
      echo "ERROR: invalid number of faults, must be an integer greater than 0" >&2;
      exit 1
fi

#Start Branch Here
read -p "Enter 1 to launch simulations or 2 to analyze results: " option
while [[ -z "$option" ]];
  do
      read -p "Enter 1 to launch simulations or 2 to analyze results: " option
done

case $option in
    
    1)
      #Read <benchmark_dir> <m2s_dir> and <benchmark_args>
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
        [-q]" benchmark_args
        while [[ -z ""$benchmark_args"" ]];
        do
            benchmark_args='-q'
      done

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
      #Run benchmark and determine number of cycles
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

      #Test if cycle max is a number

      echo "Generating faults"
      #Run Python Script and save faults to host
      ./fault_gen.py -b "$benchmark_name" "$fault_type" "$num_faults" "$cycle_max" 2>&1 >/dev/null
      #fault_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
      tar cvzf $benchmark_name"_faults"".tar.gz" "$benchmark_name""_faults" >/dev/null
      scp -q "$benchmark_name""_faults"".tar.gz" tgale@rousseau:~/ 2>&1 >/dev/null

      touch data.dat
      i=1
      while [[ $i -le $num_faults ]]; 
      do
          echo "$home_dir""/""$benchmark_name""_faults""/$[i]" >> data.dat
          ((i++))
      done

      touch launch.sh
      echo "#!/bin/bash" >> launch.sh
      echo num_faults="$num_faults" >> launch.sh
      echo benchmark_name="$benchmark_name" >> launch.sh
      echo benchmark_args="${benchmark_args// /\\ \\}" >> launch.sh
      echo benchmark_dir="$benchmark_dir" >> launch.sh
      echo m2s_path="$m2s_path" >> launch.sh

      echo 'PARAMETERS=$(awk -v line=${SLURM_ARRAY_TASK_ID} '\''{if (NR==line){ print$0; };}'\'' ./data.dat)' >> launch.sh

      echo 'srun $m2s_path --evg-sim detailed --evg-faults $PARAMETERS --evg-debug-faults debug_$SLURM_ARRAY_TASK_ID "$benchmark_dir"/"$benchmark_name" --load "$benchmark_name"_Kernels.bin ''$benchmark_args''' >> launch.sh

      scp -q -P $ssh_port data.dat launch.sh $ssh_server:~/ 2>&1 >/dev/null

      echo "Sending jobs"
      ssh $ssh_server -p $ssh_port '
      num_faults='$num_faults'
      benchmark_name='$benchmark_name'
      benchmark_args='${benchmark_args// /\\ \\}'
      benchmark_dir='$benchmark_dir'
      m2s_path='$m2s_path'
      tar xvzf $benchmark_name"_faults"".tar.gz" >/dev/null
      fault_dir_cluster=$"$benchmark_name""_faults"

      sbatch --array=1-$num_faults launch.sh
      rm "$benchmark_name""_faults"".tar.gz"
      rm m2s_training
      ' || exit 1

      echo "Jobs sent"

      #Cleaning up
      rm launch.sh
      rm data.dat
      rm "$benchmark_name""_faults"".tar.gz"
      rm -r "$benchmark_name""_faults"

      #Ending case
      ;;

    
    2)
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
      exit 1
      ;;
esac



























