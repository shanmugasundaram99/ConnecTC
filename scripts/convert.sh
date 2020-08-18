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
ELECTRODES_DATA_DIR="${SESSION_DIR}/electrodes"
ECOG_DATA_DIR="ecog"

PREFIX="sub-${SUBJECT}_ses-${SESSION}"

PYTHON2="/data/athena/share/apps/anaconda2/bin/python2.7"
PYTHON3="/data/athena/share/apps/anaconda3/bin/python"


# Initialization

mkdir bids ${SUBJECT_DIR} ${SESSION_DIR} ${RAW_NIFTY_DATA_DIR} \
    ${PROC_NIFTY_DATA_DIR} ${TRACTOGRAPHY_NIFTY_DATA_DIR} \
    ${TRACTS_DATA_DIR} ${CONNECTIVITY_DATA_DIR} ${ELECTRODES_DATA_DIR} \
    ${ECOG_DATA_DIR}

echo "stimulation_site,stimulation_begin" > ${ECOG_DATA_DIR}/events.csv

echo -e "e01\ne02\ne03\ne04\ne05\ne06\ne07\ne08\ne09\ne10\ne12\ne13\ne14\ne11" > \
    ${ECOG_DATA_DIR}/channels.csv

echo -e "e08,e04,,,,,,\ne07,e03,,,,,,\ne06,e02,,,,,,\ne05,e01,,,,,,\n,,e14,e13,e12,e11,e10,e09" > \
    ${ECOG_DATA_DIR}/locations.csv


# DICOM to NIFTY conversion (BIDS compliant)

dcm2niix -o "${RAW_NIFTY_DATA_DIR}" -z y -b y -f "${PREFIX}_acq-%p_run-0%s_dwi" ${DICOM_IMAGES_DIR}

${LOCAL_TOOLS_DIR}/name_conv.py ${RAW_NIFTY_DATA_DIR}

cp ${RAW_NIFTY_DATA_DIR}/${PREFIX}_acq-DTI*_dwi.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.nii.gz

for EXT in "bvec" "bval"
do
    cp ${RAW_NIFTY_DATA_DIR}/${PREFIX}_acq-DTI*_dwi.${EXT} \
        ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.${EXT}
done

fslmaths ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_float.nii.gz -odt float

mrconvert -force ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_float.nii.gz \
    -fslgrad ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bvec ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bval \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.mif


# Brain mask generation

bet ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_brain.nii.gz -f 0.1 -g 0 -m


# Denoising

dwidenoise -force ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_denoised.mif \
    -noise ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_noise.mif

mrconvert -force ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_denoised.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_denoised.nii.gz


# Eddy correction

echo "0 1 0 0.05" > ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.acqp

COUNT_DWI=`wc -w ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bval | cut -f1 -d' '`

rm -rf ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.index
touch ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.index

for ((i = 0; i < $((COUNT_DWI)); ++i))
do
    echo -n "1 " >> ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.index
done
echo "" >> ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.index

${LOCAL_TOOLS_DIR}/eddy_openmp --imain=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_denoised.nii.gz \
    --mask=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_brain_mask.nii.gz \
    --index=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.index \
    --acqp=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.acqp \
    --bvecs=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bvec \
    --bvals=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bval \
    --out=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy \
    --data_is_shelled


# Data interpolation

VOXEL_SIZE=1 #`fslinfo ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy.nii.gz | grep pixdim1 | cut -f2- -d' ' | sed 's/ //g'`

mrresize -force -voxel ${VOXEL_SIZE} \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.nii.gz 

mrconvert -force ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.nii.gz \
    -fslgrad ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy.eddy_rotated_bvecs \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bval \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.mif


# Interpolated brain mask generation

bet ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain.nii.gz -f 0.1 -g 0 -m

mrconvert -force ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.mif


# Registration of T1 to B0

RAW_T1_IMAGE=`ls ${RAW_NIFTY_DATA_DIR}/sub-*_ses-*_acq-*3DT1*_run-??_*.nii.gz | head -n1`

dwiextract -bzero -force ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_b0s.nii.gz

fslsplit ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_b0s.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_b0_ -t

flirt -in ${RAW_T1_IMAGE} \
    -ref ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_b0_0000.nii.gz \
    -omat ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_register.mat \
    -bins 256 -cost mutualinfo -searchrx -90 90 -searchry -90 90 \
    -searchrz -90 90 -dof 6 -interp trilinear

transformconvert -force \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_register.mat \
    ${RAW_T1_IMAGE} \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_b0_0000.nii.gz \
    flirt_import \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_register.txt

mrtransform -force \
    -linear ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_register.txt \
    ${RAW_T1_IMAGE} \
    ${PROC_NIFTY_DATA_DIR}/${PREFIX}_t1w.nii.gz


# Exporting "proc" data set

cp ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.nii.gz \
    ${PROC_NIFTY_DATA_DIR}/${PREFIX}_dwi.nii.gz

cp ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy.eddy_rotated_bvecs \
    ${PROC_NIFTY_DATA_DIR}/${PREFIX}_dwi.bvec

cp ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bval \
    ${PROC_NIFTY_DATA_DIR}/${PREFIX}_dwi.bval

cp ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain.nii.gz \
    ${PROC_NIFTY_DATA_DIR}/${PREFIX}_dwi_brain.nii.gz

cp ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.nii.gz \
    ${PROC_NIFTY_DATA_DIR}/${PREFIX}_dwi_brain_mask.nii.gz


# Computing 5tt masks

5ttgen fsl -nocrop -force ${PROC_NIFTY_DATA_DIR}/${PREFIX}_t1w.nii.gz \
    -mask ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_5tt.nii.gz

5tt2gmwmi -force ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_5tt.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_gmwm_mask.nii.gz


# Computing fODF

dwi2response msmt_5tt \
    -force -mask ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_5tt.nii.gz \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_wm_resp.txt \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_gm_resp.txt \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_csf_resp.txt

dwi2fod msmt_csd \
    -force -mask ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_wm_resp.txt \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_fod.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_gm_resp.txt \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_gm.mif \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_csf_resp.txt \
    ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_csf.mif


# Computing DTI

dtifit --data=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized.nii.gz \
    --out=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dti \
    --mask=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.nii.gz \
    --bvecs=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy.eddy_rotated_bvecs \
    --bvals=${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi.bval

cd ${TRACTOGRAPHY_NIFTY_DATA_DIR}
ln -s ${PREFIX}_dti_L1.nii.gz ${PREFIX}_dti_AD.nii.gz
cd ${CURRENT_DIR}

fslmaths ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dti_L2.nii.gz \
    -add ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dti_L3.nii.gz \
    -div 2 ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dti_RD.nii.gz


# Running tractography

for TRACTS_MLN in 1 5 10
do

    tckgen ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_fod.mif \
        ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_${TRACTS_MLN}m.tck \
        -mask ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_brain_mask.mif \
        -seed_gmwmi ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_gmwm_mask.nii.gz \
        -act ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_dwi_eddy_resized_5tt.nii.gz \
        -crop_at_gmwmi -force -select ${TRACTS_MLN}000000 -maxlength 500

    ${LOCAL_TOOLS_DIR}/scil_compress_streamlines.py \
        ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_${TRACTS_MLN}m.tck \
        ${TRACTOGRAPHY_NIFTY_DATA_DIR}/${PREFIX}_${TRACTS_MLN}m_compressed.tck

done
