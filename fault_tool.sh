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


#Checking each input option
ssh_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$1" echo ok 2>&1)
#NOT WORKING 100% YET
if [ $ssh_status == "ok" ];
  then
      ssh_server=$1
  else
      echo "ERROR: invalid ssh server" >&2;
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

if [[ $4 =~ ^[0-9]+$ ]];
  then
      num_faults=$4  
  else
      echo "ERROR: invalid number of faults, must be an integer" >&2;
      exit 1
fi

#Read <benchmark_dir> <m2s_dir> and <benchmark_args>
read -p "Please enter the benchmark directory on the cluster\
  [~/amdapp-2.5-evg/"$benchmark_name"]" benchmark_dir
while [[ -z "$benchmark_dir" ]];
do
    benchmark_dir="~/amdapp-2.5-evg/""$benchmark_name"
done

read -p "Please enter the m2s directory on the cluster\
  [~/m2s-4.2/bin/m2s]" m2s_dir
while [[ -z "$m2s_dir" ]];
do
    m2s_dir="~/m2s-4.2/bin/m2s"
done

read -p "Please enter any benchmark arguments\
  [-q]" benchmark_args
  while [[ -z ""$benchmark_args"" ]];
do
    benchmark_args='-q'
done

ssh $ssh_server '
benchmark_dir='$benchmark_dir'
m2s_dir='$m2s_dir'
' || exit 1

#Run benchmark and determine number of cycles
num_cycles=$(ssh $ssh_server '
m2s_dir='$m2s_dir'
benchmark_name='$benchmark_name'
benchmark_args='${benchmark_args// /\\ \\}'
benchmark_dir='$benchmark_dir'
$m2s_dir --evg-sim detailed "$benchmark_dir"/"$benchmark_name" \
--load "$benchmark_name""_Kernels.bin" '$benchmark_args'\
> m2s_training 2>&1 >/dev/null 
temp_num_cycles=$(grep -m2 "Cycles = " m2s_training | tail -n1 | sed "s/[^0-9]//g")
echo $temp_num_cycles
' || exit 1)

#echo Number of Cycles is "$num_cycles"

#Run Python Script and save faults to host
./fault_gen.py -b "$benchmark_name" "$fault_type" "$num_faults" 2>&1 >/dev/null
fault_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
tar cvzf $benchmark_name"_faults"".tar.gz" "$benchmark_name""_faults" > /dev/null 
scp "$benchmark_name""_faults"".tar.gz" tgale@rousseau:~/ > /dev/null

ssh $ssh_server '
num_faults='$num_faults'
benchmark_name='$benchmark_name'
benchmark_args='${benchmark_args// /\\ \\}'
benchmark_dir='$benchmark_dir'
m2s_dir='$m2s_dir'
tar xvzf $benchmark_name"_faults"".tar.gz"
fault_dir_cluster="$~/"$benchmark_name""_faults""
i=1
while [ $i -le $num_faults ]
do
  srun $m2s_dir --evg-sim detailed --evg-faults "$fault_dir_cluster""/""$i" \
  --evg-debug-faults debug_"$i" "$benchmark_dir"/"$benchmark_name" --load \
  "$benchmark_dir"/"$benchmark_name"_Kernels.bin '$benchmark_args'
  ((i++))
done
' || exit 1

echo 'Jobs Sent'




