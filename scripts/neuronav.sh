#!/bin/bash

SUBJECT=`basename ${PWD}`
SESSION="presurgical"

SUBJECT_DIR="bids/sub-${SUBJECT}"
SESSION_DIR="${SUBJECT_DIR}/ses-${SESSION}"
RAW_NIFTY_DATA_DIR="${SESSION_DIR}/raw"
NEURONAV_DATA_DIR="neuronav"
TRACTS_DATA_DIR="${SESSION_DIR}/tracts"
CONNECTIVITY_DATA_DIR="${SESSION_DIR}/connectivity"

PREFIX="sub-${SUBJECT}_ses-${SESSION}"


# merge tracts dissected manually and placed in the 'tracts' directory

mkdir ${TRACTS_DATA_DIR}/tmp
tckedit -force ${TRACTS_DATA_DIR}/*.tck ${TRACTS_DATA_DIR}/tmp/merged_tracts.tck


# resize the T1-weighted template image

INPUT_FILE=`ls ${RAW_NIFTY_DATA_DIR}/sub-*_ses-*_acq-*3DT1*_run-??_*.nii.gz | head -n1`
mrresize -force -voxel 0.5 ${INPUT_FILE} ${TRACTS_DATA_DIR}/tmp/t1w_template.nii.gz


# generate a track density image

tckmap -force -template ${TRACTS_DATA_DIR}/tmp/t1w_template.nii.gz \
    ${TRACTS_DATA_DIR}/tmp/merged_tracts.tck ${TRACTS_DATA_DIR}/tmp/tdi.nii.gz


# overlay tracts on the T1-weighted image

fslmaths ${TRACTS_DATA_DIR}/tmp/tdi.nii.gz -thr 2 -bin ${TRACTS_DATA_DIR}/tmp/tdi_bin.nii.gz

MAX_VALUE=`fslstats ${TRACTS_DATA_DIR}/tmp/t1w_template.nii.gz -R | cut -f2 -d" "`
MAX_VALUE_INT=`printf "%.0f\n" ${MAX_VALUE}`
MAX_VALUE_WITH_MARGIN=`expr ${MAX_VALUE_INT} + ${MAX_VALUE_INT} / 20`

fslmaths ${TRACTS_DATA_DIR}/tmp/tdi_bin.nii.gz -mul ${MAX_VALUE_WITH_MARGIN} \
    ${TRACTS_DATA_DIR}/tmp/tdi_bin.nii.gz

fslmaths ${TRACTS_DATA_DIR}/tmp/t1w_template.nii.gz -max ${TRACTS_DATA_DIR}/tmp/tdi_bin.nii.gz \
    ${TRACTS_DATA_DIR}/t1_with_tracts.nii.gz

rm -rf ${TRACTS_DATA_DIR}/tmp ${NEURONAV_DATA_DIR}

mkdir ${NEURONAV_DATA_DIR}

PATIENT_ID=`date +%Y%m%d`
STUDY_ID=`date +%N`
SERIES_ID=`date +%s`

nifti2dicom -a 1 -i ${TRACTS_DATA_DIR}/t1_with_tracts.nii.gz \
    -o ${NEURONAV_DATA_DIR} --patientname "${SUBJECT}" --patientid ${PATIENT_ID} \
    --studyid ${STUDY_ID} --studyinstanceuid ${STUDY_ID} \
    --seriesnumber ${SERIES_ID} --seriesinstanceuid ${SERIES_ID}


