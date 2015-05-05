#!/bin/bash

#Hardcoded defaults
#SSH_SERVER="avf_approx@129.10.53.97"

function syntax()
{
     echo  "Syntax: $0 <ssh_server> <benchmark_name> <benchmark_dir> <faults_dir> <num_faults>"
}

# Main program
if [ $# -lt 5 ]
then
    syntax
    exit 1
fi

if [ $1 == "-h" ]
then
    syntax
    exit 0
fi

ssh_server=$1
benchmark_name=$2
benchmark_dir=$3
faults_dir=$4
num_faults=$5

scp -r "$faults_dir" "$ssh_server":~/

ssh $ssh_server '
i=1
num_faults='$num_faults'
benchmark_name='$benchmark_name'
benchmark_dir='$benchmark_dir'
while [ $i -le $num_faults ]
do
  srun -N1 -n1 ~/m2s-4.2/bin/m2s --evg-sim detailed --evg-faults ~/"$benchmark_name"/"$i" \
  --evg-debug-faults debug_"$i" "$benchmark_dir"/"$benchmark_name" --load \
  "$benchmark_dir"/"$benchmark_name"_Kernels.bin -q -e -x 512 -y 512 -z 512 & 
  ((i++))
done
' || exit 1

echo 'Jobs Sent'




