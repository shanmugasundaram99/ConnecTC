#!/data/athena/share/apps/anaconda3/bin/python

import mne
import mne.io
import matplotlib

matplotlib.use('Agg')
matplotlib.rcParams['pdf.fonttype'] = 42
matplotlib.rcParams['ps.fonttype'] = 42

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import natsort
import os, sys


ecog_path = "ecog/"
connectivity_path = sys.argv[1]

offset = 8


def get_ecog_file_name_prefix(ecog_path):

    for file_name in os.listdir(ecog_path):
        file_name_prefix, file_name_extension = os.path.splitext(file_name)

        if file_name_extension.lower() == ".vhdr":
            return file_name_prefix


def get_ecog_file():
    return os.path.join(ecog_path, get_ecog_file_name_prefix(ecog_path) + '.vhdr')

def get_channels_file():
    return os.path.join(ecog_path, 'channels.csv')

def get_locations_file():
    return os.path.join(ecog_path, "locations.csv")

def get_tuned_events_file():
    return os.path.join(ecog_path, 'tuned_events.csv')

def get_effective_connectivity_file():
    return os.path.join(ecog_path, "effective_connections.csv")

def get_rois_file():
    return os.path.join(connectivity_path, "rois.csv")


def get_electrode_coords(electrode_locations, electrode_name):

    electrode_coords = np.where(electrode_locations == electrode_name)

    return electrode_coords[0][0], electrode_coords[1][0]


def load_ecog_data(electrode_locations):

    df_channels = pd.read_csv(get_channels_file(), header=None)
    channel_names = df_channels.values.ravel()

    raw = mne.io.read_raw_brainvision(vhdr_fname=get_ecog_file())
    raw.set_montage(None)

    raw.load_data()
    raw.filter(l_freq=0.5, h_freq=1000)
#    raw.filter(l_freq=0.5, h_freq=30)

    raw_data = raw.get_data()

    for i in reversed(range(len(channel_names))):

        try:
            get_electrode_coords(electrode_locations, channel_names[i])
        except:
            channel_names = np.delete(channel_names, i)
            raw_data = np.delete(raw_data, i, 0)

    renamed_info = mne.create_info(
        ch_names=channel_names.tolist(), sfreq=raw.info['sfreq'], ch_types='eeg'
    )

    return mne.io.RawArray(raw_data - np.mean(raw_data, axis=0), renamed_info)


def get_events_range(stimulation_site_row):

    return np.arange(
        stimulation_site_row[1]['time_begin'],
        stimulation_site_row[1]['time_end'],
        stimulation_site_row[1]['time_interval']
    )


def epoch_stimulation_site(stimulation_site_data, time_series, offset):

    time_series_data = time_series.get_data().T
    artifact_window_length = int(np.round(time_series.info['sfreq'] / 50))

    for stimulation_site_row in stimulation_site_data.iterrows():

        for t_start in get_events_range(stimulation_site_row):
            t_start_index = time_series.time_as_index(t_start)[0]
            time_series_data[t_start_index + offset - artifact_window_length : t_start_index + offset, :] = 0

    time_series_without_artifact = mne.io.RawArray(time_series_data.T, time_series.info)
    time_series_without_artifact.filter(l_freq=0.5, h_freq=30)

    events = np.empty((0, 3), dtype=int)

    for stimulation_site_row in stimulation_site_data.iterrows():

        for t_start in get_events_range(stimulation_site_row):
            events = np.vstack([
                events,
                np.array([time_series_without_artifact.time_as_index(t_start), 0, 1], dtype=int)
            ])

    return mne.Epochs(
        time_series_without_artifact, events, dict(stimulation=1),
        0, stimulation_site_data['time_interval'].iloc[0],
        baseline=(
            stimulation_site_data.iloc[0]['time_interval'] - 0.005,
            stimulation_site_data.iloc[0]['time_interval']
        )
    )


def get_subplot_data(electrode_locations, electrode_names):

    subplot_rows = electrode_locations.shape[0]
    subplot_cols = electrode_locations.shape[1]

    electrodes_num = len(electrode_names)
    subplot_ids = np.zeros(electrodes_num)

    for i in range(electrodes_num):

        electrode_coords = get_electrode_coords(electrode_locations, electrode_names[i])
        subplot_ids[i] = electrode_coords[0] * subplot_cols + electrode_coords[1] + 1

    return subplot_rows, subplot_cols, subplot_ids


def get_squared_distance_to_electrode(stimulation_site_record, electrode_record):

    diff_x = stimulation_site_record[1]['ras_x'] - electrode_record[1]['ras_x']
    diff_y = stimulation_site_record[1]['ras_y'] - electrode_record[1]['ras_y']
    diff_z = stimulation_site_record[1]['ras_z'] - electrode_record[1]['ras_z']

    return diff_x * diff_x + diff_y * diff_y + diff_z * diff_z


def get_nearest_electrodes():

    df_rois = pd.read_csv(get_rois_file())

    df_electrode_rois = df_rois.loc[df_rois['label'].str.contains("e")]
    df_stimulation_site_rois = df_rois.loc[df_rois['label'].str.contains("s")]

    nearest_electrodes = {}
    for stimulation_site_record in df_stimulation_site_rois.iterrows():

        min_dist = np.infty

        for electrode_record in df_electrode_rois.iterrows():

            cur_dist = get_squared_distance_to_electrode(stimulation_site_record, electrode_record)

            if cur_dist < min_dist:

                min_dist = cur_dist
                nearest_electrodes[stimulation_site_record[1]['label']] = electrode_record[1]['label']

    return nearest_electrodes


def plot_local_extrema(data, plot_ylim, offset, p1_lower_bound = 20, p1_upper_bound = 150, min_diff = 0.00002):

    n1 = 0
    n2 = 0
    p1 = 0

    arg_min = np.argmin(data[p1_lower_bound : p1_upper_bound])

    if arg_min > 0 and arg_min < p1_upper_bound - 1:

        local_min = p1_lower_bound + arg_min
        plt.plot([local_min, local_min], plot_ylim, 'k:')

        l_bound = local_min - p1_lower_bound
        r_bound = local_min + p1_lower_bound

        r_diff = data[r_bound] - data[local_min]
        l_diff = data[l_bound] - data[local_min]

        if l_diff > min_diff and r_diff > min_diff:

            p1 = local_min
            plt.plot([l_bound, l_bound], plot_ylim, 'k:')
            plt.plot([r_bound, r_bound], plot_ylim, 'k:')

    return n1, p1, n2


def plot_averages(
    stimulation_site_data, epochs, electrode_locations,
    electrode_names, nearest_electrodes, offset, data_path, prefix
):

    filter_name = "band30Hz"

    subplot_rows, subplot_cols, subplot_ids = get_subplot_data(electrode_locations, electrode_names)
    plt.figure(figsize=(2.5 * subplot_cols, 2 * subplot_rows))

    epochs.load_data()
    epoch_data = epochs.get_data()

    avg_data = np.mean(epoch_data, axis=0)

    plot_xlim = [offset, np.minimum(500, avg_data.shape[1])]
    plot_ylim = [-0.0008, 0.0003]

    p1_delays = np.zeros(len(electrode_names))
    p1_amplitudes = np.zeros_like(p1_delays)

    for electrode_name in natsort.natsorted(electrode_names):

        electrode_id = electrode_names.index(electrode_name)

        plt.subplot(subplot_rows, subplot_cols, subplot_ids[electrode_id])

        for j in range(epoch_data.shape[0]):
            plt.plot(
                np.arange(plot_xlim[0], plot_xlim[1]), 
                epoch_data[j, electrode_id, plot_xlim[0] : plot_xlim[1]], 
                color=(0.75, 0.75, 0.75)
            )

        data = avg_data[electrode_id]

        n1_key, p1_key, n2_key = plot_local_extrema(data, plot_ylim, offset)

        n1_ms = np.round(n1_key / (0.001 * epochs.info['sfreq']))
        p1_ms = np.round(p1_key / (0.001 * epochs.info['sfreq']))
        n2_ms = np.round(n2_key / (0.001 * epochs.info['sfreq']))

        p1_delays[electrode_id] = p1_ms
        p1_amplitudes[electrode_id] = data[p1_key]

        if nearest_electrodes[stimulation_site_data.iloc[0]['stimulation_site']] == electrode_name:
            plt.plot(np.arange(plot_xlim[0], plot_xlim[1]), data[plot_xlim[0] : plot_xlim[1]], color='red', linewidth=2)    
        else:
            plt.plot(np.arange(plot_xlim[0], plot_xlim[1]), data[plot_xlim[0] : plot_xlim[1]], color='blue', linewidth=2)    

        if subplot_ids[electrode_id] + subplot_cols in subplot_ids:
            plt.xticks([])
        else:
            plt.xticks(
                np.arange(0, data.shape[0], 0.1 * epochs.info['sfreq']),
                np.arange(0, data.shape[0] / (0.001 * epochs.info['sfreq']), 100, dtype=int)
            )

        if subplot_ids[electrode_id] - 1 in subplot_ids:
            plt.yticks([])
        else:
            plt.yticks([-0.0005, 0])

        plt.xlim(plot_xlim)
        plt.ylim(plot_ylim)

        plt.title("%s | %d" % (electrode_name, p1_ms))

    images_path = "%s/images" % data_path
    if not os.path.isdir(images_path):
        os.mkdir(images_path)

    plt.savefig(
        "%s/stim_without_artifact_%s_%sHz_%s_%s_average.png" % (
            images_path, 
            stimulation_site_data.iloc[0]['stimulation_site'],
            stimulation_site_data.iloc[0]['frequency'],
            prefix, filter_name
        )
    )
    plt.close()

    return p1_delays, p1_amplitudes


# mne.set_log_level('CRITICAL')

df_locations = pd.read_csv(get_locations_file(), header=None)
electrode_locations = df_locations.values

common_avg = load_ecog_data(electrode_locations)

nearest_electrodes = get_nearest_electrodes()

df_events = pd.read_csv(get_tuned_events_file())
stimulation_sites = natsort.natsorted(df_events['stimulation_site'].unique())

stimulation_sites_num = len(stimulation_sites)
electrodes_num = common_avg.info['nchan']

p1_delays_matrix = np.zeros([stimulation_sites_num, electrodes_num])
p1_amplitudes_matrix = np.zeros_like(p1_delays_matrix)

for i in range(stimulation_sites_num):

    stimulation_site_data = df_events.loc[df_events['stimulation_site'] == stimulation_sites[i]]

    epochs_common_avg = epoch_stimulation_site(stimulation_site_data, common_avg, offset)

    p1_delays, p1_amplitudes = plot_averages(
        stimulation_site_data, epochs_common_avg, electrode_locations, 
        common_avg.info['ch_names'], nearest_electrodes, offset, ecog_path, 'common_avg'
    )

    p1_delays_matrix[i, :] = p1_delays
    p1_amplitudes_matrix[i, :] = p1_amplitudes


effective_connectivity_data = pd.DataFrame(
    columns=['stimulation_site', 'electrode', 'p1_delay', 'p1_amplitude']
)

for i in range(stimulation_sites_num):

    stimulation_site_data = df_events.loc[df_events['stimulation_site'] == stimulation_sites[i]]

    p1_delays_vector = p1_delays_matrix[i, :]
    p1_delays_vector[p1_delays_vector == 0] = np.nan

    p1_amplitudes_vector = p1_amplitudes_matrix[i, :]

    for electrode_name in natsort.natsorted(common_avg.info['ch_names']):

        electrode_id = common_avg.info['ch_names'].index(electrode_name)

        effective_connectivity_record = {
            'stimulation_site': stimulation_site_data.iloc[0]['stimulation_site'],
            'electrode': electrode_name
        }
        if p1_delays_vector[electrode_id] > 0:
            effective_connectivity_record['p1_delay'] = p1_delays_vector[electrode_id]
            effective_connectivity_record['p1_amplitude'] = p1_amplitudes_vector[electrode_id]
        else:
            effective_connectivity_record['p1_delay'] = np.nan
            effective_connectivity_record['p1_amplitude'] = np.nan

        effective_connectivity_data = effective_connectivity_data.append(
            effective_connectivity_record, ignore_index=True
        )

effective_connectivity_data.to_csv(get_effective_connectivity_file(), index=False)

