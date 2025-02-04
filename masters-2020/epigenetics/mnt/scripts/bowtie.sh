#!/usr/bin/env bash
# Original https://github.com/JetBrains-Research/washu
# Author os@jetbrains.com.com

# Stop exec on error.
set -e

which bowtie &>/dev/null || { echo "ERROR: bowtie not found!"; exit 1; }
which samtools &>/dev/null || { echo "ERROR: samtools not found!"; exit 1; }

>&2 echo "Batch bowtie $@"
if [[ $# -lt 3 ]]; then
    echo "Need 3 parameters! <GENOME> <INDEXES> <WORK_DIR>"
    exit 1
fi

GENOME=$1
INDEXES=$2
WORK_DIR=$3

cd ${WORK_DIR}

# Fails with large indexes, create soft link to indexes in working directory as a workaround
# export BOWTIE_INDEXES=${INDEXES}
if [[ ! -d "${WORK_DIR}/indexes" ]]; then
    ln -sf ${INDEXES} ${WORK_DIR}/indexes
fi

# Bowtie fails with large indexes, explicitly set
if [[ -f indexes/${GENOME}.1.ebwtl ]]; then
    INDEX_ARG="--large-index"
else
    INDEX_ARG=""
fi


# For paired end alignment processing
PROCESSED=()

for FILE in $(find . -name '*.f*q' | sed 's#\./##g' | sort)
do :
    if $(echo "${PROCESSED[@]}"  | fgrep -q "${FILE}");
    then
        echo "$FILE was already processed"
        continue
    fi

    # Assumption: the only difference between paired-end read files is _1 and _2 / _R1 and _R2
    FILE_PAIRED=""
    if $(echo "${FILE}"  | fgrep -q "_1"); then
        FILE_PAIRED=$(echo "${FILE}" | sed 's#_1#_2#g')
        NAME=$(echo ${FILE} | sed 's#_1##g' | sed -r 's#^.*/##g' | sed -r 's#\.f.*q$##g')
    elif $(echo "${FILE}"  | fgrep -q "_R1"); then
        FILE_PAIRED=$(echo "${FILE}" | sed 's#_R1#_R2#g')
        NAME=$(echo ${FILE} | sed 's#_R1##g' | sed -r 's#^.*/##g'| sed -r 's#\.f.*q$##g')
    else
        NAME=$(echo ${FILE} | sed -r 's#\.f.*q$##g')
    fi

    # Check FILE_PAIRED
    if [[ -f "${FILE_PAIRED}" ]]; then
        echo "PAIRED END reads detected: $FILE and $FILE_PAIRED"
        # Mark it as already processed
        PROCESSED+=("${FILE_PAIRED}")
    fi

    ID=${NAME}_${GENOME}
    BAM_NAME="${ID}.bam"

    if [[ -f "${BAM_NAME}" ]]; then
        echo "   [Skipped] ${WORK_DIR}/${BAM_NAME} already exists."
        continue
    fi

    # Bowtie command line options used
    # -p/--threads <int> number of alignment threads to launch (default: 1)
    # -S/--sam           write hits in SAM format
    # -t/--time          print wall-clock time taken by search phases
    # -m <int>           suppress all alignments if > <int> exist (def: no limit)
    # -v <int>           report end-to-end hits w/ <=v mismatches; ignore qualities
    # --best             hits guaranteed best stratum; ties broken by quality
    # --strata           hits in sub-optimal strata aren't reported (requires --best)
    if [[ -f "${FILE_PAIRED}" ]]; then
        bowtie -p 6 -St -m 1 -v 3 --best --strata ${INDEX_ARG} ${GENOME} \
            -1 ${FILE} -2 ${FILE_PAIRED} ${ID}.sam 2>&1 |\
            tee ${NAME}_bowtie_${GENOME}.log
    else
        bowtie -p 6 -St -m 1 -v 3 --best --strata ${INDEX_ARG} ${GENOME} ${FILE} ${ID}.sam 2>&1 |\
            tee ${NAME}_bowtie_${GENOME}.log
    fi
    samtools view -bS ${ID}.sam -o ${ID}_not_sorted.bam
    samtools sort ${ID}_not_sorted.bam -o ${BAM_NAME}

    # Cleanup
    rm ${ID}.sam ${ID}_not_sorted.bam

done

# Cleanup indexes soft link
if [[ -d "${WORK_DIR}/indexes" ]]; then
    rm ${WORK_DIR}/indexes
fi


>&2 echo "Done. Batch bowtie $@"