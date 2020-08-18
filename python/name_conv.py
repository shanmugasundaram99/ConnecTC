#!/data/athena/share/apps/anaconda3/bin/python

import sys, os
import re

data_dir = sys.argv[1]
file_names = os.listdir(data_dir)

for file_name in file_names:
    pattern = re.compile('sub-(.*)_ses-(.*)_acq-(.*)_run-(.*)_dwi(.*)')
    match = pattern.match(file_name)

    output_groups = []
    for match_group in match.groups():
        output_groups.append(match_group.replace("_", ""))

    output_file_name = "sub-%s_ses-%s_acq-%s_run-%02d_dwi%s" % (
        output_groups[0], output_groups[1], 
        output_groups[2], int(output_groups[3]), 
        output_groups[4]
    )

    input_path = os.path.join(data_dir, file_name)
    output_path = os.path.join(data_dir, output_file_name)

    os.rename(input_path, output_path)



