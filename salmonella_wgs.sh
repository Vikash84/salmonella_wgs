#!/usr/bin/env bash

usage() { 
 echo "Usage: $0
 Required:
 -1       Input forward fastq
 -2       Input reverse fastq
 -o       specify output directory
 
 Options:
 --qc     run quality check (Quast, kraken2, CheckM) [Disabled by default]
 --mlst   run MLST using MentaliST [Disabled by default]
 --amr    run AMR profiling using abricate [Disabled by default]
 -t       Number of threads [Default: 1]

 "
}

# initialize variables
qc_run=false
mlst_run=false
amr_run=false
n_threads=1

# parse arguments
opts=`getopt -o h1:2:o:t: -l qc,mlst,amr \
      -- "$@"`
eval set -- "$opts"

while true; do
  case "$1" in
    -1) fastq_1=$2; shift 2 ;;
    -2) fastq_2=$2; shift 2 ;;
    -o) OUT_DIR=$2; shift 2 ;;
    -t) n_threads=$2; shift 2 ;;
    --mlst) mlst_run=true; shift ;;
    --qc) qc_run=true; shift ;;
    --amr) amr_run=true; shift ;;
    --) shift; break ;;
    -h) usage; shift; break ;;
  esac
done


# Read trimming using fastp #
fastp_exe() {
  time=$(date +"%T")
  echo "[$time] Read trimming using fastp"

  source /opt/galaxy/tool_dependencies/_conda/bin/activate /home/$USER/.conda/envs/fastp
  cleaned_fastq_1=/scratch/$USER/tmp/$(basename ${fastq_1%.*}).tmp
  cleaned_fastq_2=/scratch/$USER/tmp/$(basename ${fastq_2%.*}).tmp
  fastp -i $fastq_1 -I $fastq_2 \
        -o $cleaned_fastq_1 \
        -O $cleaned_fastq_2 \
        -w $n_threads
}

# Read Classification using kraken2
kraken2_exe() {
  time=$(date +"%T")
  echo "[$time] Read classification using kraken2"
  
  source /opt/galaxy/tool_dependencies/_conda/bin/activate /opt/miniconda2/envs/kraken2-2.0.7_beta
  kraken2 $fastq_1 $fastq_2 \
          --paired \
          --threads $n_threads \
          --database /data/ref_databases/kraken2/minikraken2_v2_8GB \
          --use-names \
          --report $OUT_DIR/kraken2_res/kraken2_report
}

# Genome assembly using shovill
shovill_exe() {
  time=$(date +"%T")
  echo "[$time] Genome assembly using shovill"
  
  source /opt/galaxy/tool_dependencies/_conda/bin/activate /opt/miniconda2/envs/shovill-1.0.4
  shovill --outdir $OUT_DIR/shovill_res \
          --R1 $cleaned_fastq_1 \
          --R2 $cleaned_fastq_2 \
          --gsize 4.5M \
          --cpus $n_threads \
          --force
}

# Completion/Contamination check using checkm
checkm_exe() {
  time=$(date +"%T")
  echo "[$time] Checking assembly using CheckM"
  
  source /opt/galaxy/tool_dependencies/_conda/bin/activate /home/$USER/.conda/envs/checkm
  checkm taxonomy_wf species "Salmonella enterica" \
                $OUT_DIR/shovill_res/contigs.fa \
                $OUT_DIR/checkm_res \
                -t $n_threads \
                -x fasta \
                -f $OUT_DIR/${SGE_TASK_ID}_run/checkm_report.tsv \
                --tmpdir /scratch/$USER/tmp/

}

# Assembly statistics using quast
quast_exe(){
  time=$(date +"%T")
  echo "[$time] Calculating assembly statistics using Quast"
  
  source /opt/galaxy/tool_dependencies/_conda/bin/activate /opt/miniconda2/envs/quast-5.0.2
  quast --fast \
        -t 12  \
        -o $OUT_DIR/quast_res \
        $OUT_DIR/shovill_res/contigs.fa
}

# MLST typing using mentalist
mentalist_exe() {
  time=$(date +"%T")
  echo "[$time] MLST typing using MentaliST"
  
  source /opt/galaxy/tool_dependencies/_conda/bin/activate __mentalist@0.1.9
  kmerdb="/opt/galaxy/tool-data/mentalist_databases/salmonella_enterobase_cgmlst_k31_2018-07-26/salmonella_enterobase_cgmlst_k31_2018-07-26.jld"
  mentalist call -o $OUT_DIR/mentalist_res/allele_profile \
            -s $(echo ${fastq_1%.*}) \
            --db $kmerdb \
            $cleaned_fastq_1 \
            $cleaned_fastq_2
}

# AMR profiling using abricate
abricate_exe() {
  time=$(date +"%T")
  echo "[$time] AMR profiling using abricate"
  
  source /opt/galaxy/tool_dependencies/_conda/bin/activate /opt/miniconda2/envs/abricate-0.8.7
  abricate --db card \
           --threads n_threads \
           $OUT_DIR/shovill_res/contigs.fa > $OUT_DIR/abricate_res/amr_profile.tab
}


#### Main ####

# Print run summary
echo "Salmonella WGS Pipeline Summary:

Quality Check:      $qc_run
MLST Typing:        $mlst_run
AMR Profiling:      $amr_run
Output Directory:   $OUT_DIR
Number of Threads:  $n_threads
"


# Check dependencies

# Read trimming
fastp_exe

# Read QC
if [ $qc_run == true ]; then
  mkdir -p $OUT_DIR/kraken2_res
  kraken2_exe
fi

# MLST
if [ $mlst_run == true ]; then
  mkdir -p $OUT_DIR/mentalist_res
  mentalist_exe
fi

# Genome assembly
mkdir -p $OUT_DIR/shovill_res
shovill_exe

# Remove tmp files
rm $cleaned_fastq_1
rm $cleaned_fastq_2

# Assembly QC
if [ $qc_run == true ]; then
  mkdir -p $OUT_DIR/checkm_res
  checkm_exe
  mkdir -p $OUT_DIR/quast_res
  quast_exe
fi

# AMR Profiling
if [ $amr_run == true ]; then
  mkdir -p $OUT_DIR/abricate_res
  abricate_exe
fi

