#!/bin/bash

SUBJECT=`basename ${PWD}`
SESSION="presurgical"

DICOM_IMAGES_DIR="dicom"
LOCAL_TOOLS_DIR="/data/athena/share/apps/bin"

CURRENT_DIR="${PWD}"
SUBJECT_DIR="bids/sub-${SUBJECT}"
SESSION_DIR="${SUBJECT_DIR}/ses-${SESSION}"
RAW_NIFTY_DATA_DIR="${SESSION_DIR}/raw"
PROC_NIFTY_DATA_DIR="${SESSION_DIR}/proc"
TRACTOGRAPHY_NIFTY_DATA_DIR="${SESSION_DIR}/tractography"
TRACTS_DATA_DIR="${SESSION_DIR}/tracts"
CONNECTIVITY_DATA_DIR="${SESSION_DIR}/connectivity"
STREAMLINES_DATA_DIR="${CONNECTIVITY_DATA_DIR}/streamlines"
ELECTRODES_DATA_DIR="${SESSION_DIR}/electrodes"

PREFIX="sub-${SUBJECT}_ses-${SESSION}"

PYTHON2="/data/athena/share/apps/anaconda2/bin/python2.7"
PYTHON3="/data/athena/share/apps/anaconda3/bin/python"


# Load ROI coordinates from the MI-Brain project file .MITK

cd ${ELECTRODES_DATA_DIR}

if [ -d "tmp" ]; then
    rm -rf tmp
fi

mkdir tmp
unzip *.mitk -d tmp

OUTPUT_ROI_TMP_FILE="tmp/_rois.csv"

if [ -f ${OUTPUT_ROI_TMP_FILE} ]; then
    rm -rf ${OUTPUT_ROI_TMP_FILE}
fi

touch ${OUTPUT_ROI_TMP_FILE}

for ROI_FILE in tmp/*.bdo
do
    ROI_NAME=`echo ${ROI_FILE} | sed 's/.bdo//g' | cut -f2 -d"_"`

    ROI_COORDS=`grep 'origin' ${ROI_FILE} | sed 's/<origin//'g | sed 's/\/>//'g | \
        sed 's/x="//g' | sed 's/" y="/,/g' | sed 's/" z="/,/g' | \
        sed 's/"//g' | sed 's/ //g'`

    ROI_X=`echo ${ROI_COORDS} | cut -f1 -d","`
    ROI_Y=`echo ${ROI_COORDS} | cut -f2 -d","`
    ROI_Z=`echo ${ROI_COORDS} | cut -f3 -d","`

    ROI_X_RAS=`echo "-1 * ${ROI_X}" | bc`
    ROI_Y_RAS=`echo "-1 * ${ROI_Y}" | bc`
    ROI_Z_RAS=${ROI_Z}

    echo "${ROI_NAME},${ROI_X_RAS},${ROI_Y_RAS},${ROI_Z_RAS}" >> ${OUTPUT_ROI_TMP_FILE}

done

cd ${CURRENT_DIR}


# Store ROI coordinates converted to RAS

echo "label,ras_x,ras_y,ras_z" > ${CONNECTIVITY_DATA_DIR}/rois.csv
cat ${ELECTRODES_DATA_DIR}/${OUTPUT_ROI_TMP_FILE} | sort -n >> ${CONNECTIVITY_DATA_DIR}/rois.csv

rm -rf ${ELECTRODES_DATA_DIR}/tmp


# Run post-surgical tractography

if [ -d ${STREAMLINES_DATA_DIR} ]; then
    rm -rf ${STREAMLINES_DATA_DIR}
fi

mkdir ${STREAMLINES_DATA_DIR}

RADIUS=5
SEEDS_NUM=2000000
MAX_ANGLE=30

STIMULATION_SITES=`grep "^s" ${CONNECTIVITY_DATA_DIR}/rois.csv`
ELECTRODES=`grep "^e" ${CONNECTIVITY_DATA_DIR}/rois.csv`

for STIMULATION_SITE in ${STIMULATION_SITES}
do
    STIMULATION_SITE_LABEL=`echo ${STIMULATION_SITE} | cut -f1 -d","`
    STIMULATION_SITE_COORDS=`echo ${STIMULATION_SITE} | cut -f2-4 -d","`

    for ELECTRODE in ${ELECTRODES}
    do
        ELECTRODE_LABEL=`echo ${ELECTRODE} | cut -f1 -d","`
        ELECTRODE_COORDS=`echo ${ELECTRODE} | cut -f2-4 -d","`

        echo "${STIMULATION_SITE_LABEL} ${ELECTRODE_LABEL}"

        tckgen ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_fod.mif \
            ${STREAMLINES_DATA_DIR}/${STIMULATION_SITE_LABEL}_${ELECTRODE_LABEL}.tck \
            -mask ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.mif \
            -seeds ${SEEDS_NUM} -maxlength 500 \
            -seed_sphere ${STIMULATION_SITE_COORDS},${RADIUS} \
            -include ${ELECTRODE_COORDS},${RADIUS} \
            -angle ${MAX_ANGLE} -force -info

        stat_streamlines.py "${STIMULATION_SITE_LABEL}" "${ELECTRODE_LABEL}" \
            ${STREAMLINES_DATA_DIR}/${STIMULATION_SITE_LABEL}_${ELECTRODE_LABEL}.tck \
            ${CONNECTIVITY_DATA_DIR}/connections.csv

    done
done