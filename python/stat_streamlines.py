#!/data/athena/share/apps/anaconda3/bin/python

import numpy as np
import nibabel as nib
import dipy.tracking.utils
import pandas as pd
import os, sys


stimulation_site = sys.argv[1]
electrode = sys.argv[2]
tck_file_name = sys.argv[3]
csv_file_name = sys.argv[4]

tck_file = nib.streamlines.load(tck_file_name)
streamline_lengths = list(dipy.tracking.utils.length(tck_file.streamlines))

csv_column_labels = [
    'stimulation_site', 'recording_electrode', 'streamlines_num', 
    'min_len', 'max_len', 'avg_len', 'median_len', 'std_len',
    'n1_delay', 'n1_amplitude', 'p1_delay', 'p1_amplitude'
]

if os.path.isfile(csv_file_name):
    df = pd.read_csv(csv_file_name)
else:
    df = pd.DataFrame(columns=csv_column_labels)

df = df.append({
    'stimulation_site': stimulation_site, 
    'recording_electrode': electrode, 
    'streamlines_num': len(streamline_lengths),
    'min_len': np.min(streamline_lengths),
    'max_len': np.max(streamline_lengths),
    'avg_len': np.mean(streamline_lengths), 
    'median_len': np.median(streamline_lengths),
    'std_len': np.std(streamline_lengths) 
}, ignore_index=True)

df.to_csv(csv_file_name, index=False)



