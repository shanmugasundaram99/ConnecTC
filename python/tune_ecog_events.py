#!/data/athena/share/apps/anaconda3/bin/python

import mne
import mne.io
import numpy as np
import pandas as pd
import os

from scipy import stats
from datetime import datetime, timedelta


ecog_path = "ecog/"


z_score_threshold = 5 # 10
artifact_onset_tolerance = 5

stimulation_frequency = 2              # [Hz]
stimulation_current = 5                # [mA]
stimulation_pulse_width = 0.001        # [s]
stimulation_time_interval = 0.49975    # [s]
stimulation_max_duration = 6           # [s]


def get_ecog_file_name_prefix(ecog_path):

    for file_name in os.listdir(ecog_path):
        file_name_prefix, file_name_extension = os.path.splitext(file_name)

        if file_name_extension.lower() == ".vhdr":
            return file_name_prefix


def fix_brain_vision_export(ecog_path, ecog_file_name_prefix):

    for ecog_file_name_extension in ['.vhdr', '.vmrk']:

        f = open(os.path.join(ecog_path, ecog_file_name_prefix + ecog_file_name_extension), 'r+')
        first_line = f.readline()

        if "BrainVision" in first_line:
            f.seek(0)
            f.write(first_line.replace("BrainVision", "Brain Vision"))

        f.close()


ecog_file_name_prefix = get_ecog_file_name_prefix(ecog_path)
fix_brain_vision_export(ecog_path, ecog_file_name_prefix)

raw = mne.io.read_raw_brainvision(
    vhdr_fname=os.path.join(ecog_path, ecog_file_name_prefix + '.vhdr')
)
raw.set_montage(None)

raw.load_data()
raw.filter(l_freq=0.5, h_freq=1000)
raw.notch_filter(freqs=50, notch_widths=9)

experiment_start_time = datetime.utcfromtimestamp(raw.info['meas_date'][0])
stimulation_date = experiment_start_time.strftime("%Y-%m-%d")

csv_column_labels = [
    'stimulation_site', 'frequency', 'current', 'pulse_width', 
    'time_begin', 'time_end', 'time_interval'
]

events_data = pd.read_csv(
    os.path.join(ecog_path, "events.csv"), header=0
)

tuned_events_data = pd.DataFrame(columns=csv_column_labels)

for event_record in events_data.iterrows():

    stimulation_begin_datetime = datetime.strptime(
        "%s %s" % (stimulation_date, event_record[1]['stimulation_begin']), "%Y-%m-%d %H:%M/%S"
    )

    stimulation_end_datetime = stimulation_begin_datetime + timedelta(seconds = stimulation_max_duration)

    events_range = np.arange(
        (stimulation_begin_datetime - experiment_start_time).total_seconds(),
        (stimulation_end_datetime - experiment_start_time).total_seconds(),
        stimulation_time_interval
    )

    artifact_onsets = []
    for t_start in events_range:

        raw_data = raw.copy().crop(tmin=t_start, tmax=t_start + stimulation_time_interval).get_data()
        z_score_data = stats.zscore(np.max(np.abs(raw_data), axis=0))

        artifact_onsets.append(np.argmax(z_score_data > z_score_threshold))

    substring_lengths = []
    current_substring_length = 0
    reference_artifact_onset = np.median(artifact_onsets)

    for artifact_onset in artifact_onsets:

        if np.abs(artifact_onset - reference_artifact_onset) < artifact_onset_tolerance:
            current_substring_length += 1
        else:
            current_substring_length = 0

        substring_lengths.append(current_substring_length)

    max_substring_begin = np.argmax(substring_lengths) - np.max(substring_lengths) + 1
    max_substring_end = np.argmax(substring_lengths) + 1

    average_onset_shift = np.mean(artifact_onsets[max_substring_begin : max_substring_end]) / raw.info['sfreq'] + stimulation_time_interval * max_substring_begin

    tuned_stimulation_begin_time = events_range[0] + average_onset_shift
    tuned_stimulation_end_time = tuned_stimulation_begin_time + stimulation_time_interval * (max_substring_end - max_substring_begin - 0.5)

    tuned_events_data = tuned_events_data.append({
        'stimulation_site': event_record[1]['stimulation_site'],
        'frequency': np.round(stimulation_frequency),
        'current': np.round(stimulation_current),
        'pulse_width': stimulation_pulse_width,
        'time_begin': np.round(tuned_stimulation_begin_time, 3),
        'time_end': np.round(tuned_stimulation_end_time, 3),
        'time_interval': stimulation_time_interval
    }, ignore_index=True)

tuned_events_data.to_csv(os.path.join(ecog_path, "tuned_events.csv"), index=False)


