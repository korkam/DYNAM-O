%%%% Example script showing how to compute time-frequency peaks and slow oscillation power and phase %%%%

%% Clear workspace and close plots
clear; close all;

%% Load example EEG data
load('example_data/example_data.mat', 'EEG', 'stages', 'Fs', 't');

%% Add necessary functions to path
addpath(genpath('./all_functions'))

%% Compute spectrogram 
% For more information on the multitaper spectrogram parameters and
% implementation visit: https://github.com/preraulab/multitaper

freq_range = [0,30]; % frequency range to compute spectrum over (Hz)
taper_params = [2,3]; % [time halfbandwidth product, number of tapers]
time_window_params = [1,0.05]; % [time window, time step] in seconds
nfft = 2^10; % zero pad data to this minimum value for fft
detrend = 'off'; % do not detrend 
weight = 'unity'; % each taper is weighted the same
ploton = false; % do not plot out

[spect,stimes,sfreqs] = multitaper_spectrogram_mex(EEG, Fs, freq_range, taper_params, time_window_params, nfft, detrend, weight, false);

%% Compute baseline spectrum used to flatten EEG data spectrum
artifacts = detect_artifacts(EEG, Fs); % detect artifacts in EEG
artifacts_stimes = logical(interp1(t, double(artifacts), stimes, 'nearest')); % get artifacts occuring at spectrogram times
    
% Get lights off and lights on times
lightsonoff_mins = 5; 
time_range(1) = max( min(t(~ismember(stages,[5,0])))-lightsonoff_mins*60, 0); % 5 min before first non-wake stage 
time_range(2) = min( max(t(~ismember(stages,[5,0])))+lightsonoff_mins*60, max(t)); % 5 min after last non-wake stage

% Get invalid times for baseline computation
invalid_times = (stimes > time_range(2) & stimes < time_range(1)) & artifacts_stimes;

spect_bl = spect; % copy spectogram
spect_bl(:,invalid_times) = NaN; % turn artifact times into NaNs for percentile computation
spect_bl(spect_bl==0) = NaN; % Turn 0s to NaNs for percentile computation

baseline_ptile = 2; % using 2nd percentile of spectrogram as baseline
baseline = prctile(spect_bl, baseline_ptile, 2); % Get baseline

%% Pick a segment of the spectrogram to extract peaks from 
% Use only a segment of the spectrogram (13000-21000 seconds) for example to save computing time
[~,start] = min(abs(13000 - stimes)); 
[~,last] = min(abs(21000 - stimes)); 
spect_in = spect(:, start:last);
stimes_in = stimes(start:last);

%% Compute time-frequency peaks
[matr_names, matr_fields, peaks_matr,~,~, pixel_values] = extract_TFpeaks(spect_in, stimes_in, sfreqs, baseline);

%% Filter out noise peaks
[feature_matrix, feature_names, xywcntrd, combined_mask] = filterpeaks_watershed(peaks_matr, matr_fields, matr_names, pixel_values);

%% Extract time-frequency peak times and frequencies
peak_times = xywcntrd(:,1);
peak_freqs = xywcntrd(:,2);

%% Compute SO power and SO phase
% Exclude WAKE stages from analyses
stage_exclude = ismember(stages, 5);

% Compute SO power
% use ('plot_flag', true) to plot directly from this function call
[SOpow_mat, freq_cbins, SOpow_cbins, ~, ~, peak_SOpow, peak_inds] = SOpower_histogram(EEG, Fs, peak_freqs, peak_times, 'stage_exclude', stage_exclude, 'artifacts', artifacts); 

% Compute SO phase
% use ('plot_flag', true) to plot directly from this function call
% Using negation of EEG because Lunesta data is phase flipped
[SOphase_mat, ~, SOphase_cbins, ~, ~, peak_SOphase, ~] = SOphase_histogram(-EEG, Fs, peak_freqs, peak_times, 'stage_exclude', stage_exclude, 'artifacts', artifacts);

% To use a custom precomputed SO phase filter, use the SOphase_filter argument
% custom_SOphase_filter = designfilt('bandpassfir', 'StopbandFrequency1', 0.1, 'PassbandFrequency1', 0.4, ...
%                        'PassbandFrequency2', 1.75, 'StopbandFrequency2', 2.05, 'StopbandAttenuation1', 60, ...
%                        'PassbandRipple', 1, 'StopbandAttenuation2', 60, 'SampleRate', 256);
% [SOphase_mat, ~, SOphase_cbins, TIB_phase, PIB_phase] = SOphase_histogram(EEG, Fs, peak_freqs, peak_times, 'stage_exclude', stage_exclude, 'artifacts', artifacts, ...
%                                                                           'SOphase_flter', custom_SOphase_filter);

                                                                      
%% Plot

% Create empty figure
fig = figure;
ax = figdesign(7,2,'type','usletter','orient','portrait','merge',{1:6, 7:10, [11,13], [12,14]}, 'margins',[0.03 .07 .06 .11 .16, 0.08]);

% Split axis for hypnogram and spectrogram
hypn_spect_ax = split_axis(ax(1), [0.67, 0.33], 1);

% Link axes of appropriate plots
linkaxes([hypn_spect_ax(1), hypn_spect_ax(2), ax(2)], 'x');

% Set yaxis limits
ylimits = [4,25];

% Plot hypnogram
axes(hypn_spect_ax(2));
hypnoplot(stimes, interp1(t,stages,stimes,'nearest'));
title('Hypnogram and Spectrogram')

% Plot spectrogram
axes(hypn_spect_ax(1))
imagesc(stimes, sfreqs, nanpow2db(spect));
axis xy; % flip axes
colormap(hypn_spect_ax(1), 'jet');
spect_clims = climscale; % change color scale for better visualization
c = colorbar_noresize; % set colobar
c.Label.String = 'Power (dB)'; % colobar label
c.Label.Rotation = -90; % rotate colorbar label
c.Label.VerticalAlignment = "bottom";
ylabel('Frequency (Hz)');
xlabel('')
ylim(ylimits);
xticklabels({});
[~, sh] = scaleline(hypn_spect_ax(1), 3600,'1 Hour' );
sh.FontSize = 10;


% Plot time-frequency peak scatterplot
axes(ax(2))
peak_height = feature_matrix(:,strcmp(feature_names, 'Height')); % get height of each peak
pmax = prctile(peak_height,95); % get 95th ptile of heights
peak_height(peak_height>pmax) = pmax; % don't plot larger than 95th ptile or else dots could obscure other things on the plot
scatter(peak_times(peak_inds), peak_freqs(peak_inds), peak_height(peak_inds)./12, peak_SOphase(peak_inds), 'filled'); % scatter plot all peaks
colormap(ax(2),circshift(hsv(2^12),-400))
c = colorbar_noresize;
c.Label.String = 'Phase (radians)';
c.Label.Rotation = -90;
c.Label.VerticalAlignment = "bottom";
set(c,'xtick',([-pi -pi/2 0 pi/2 pi]),'xticklabel',({'-\pi', '-\pi/2', '0', '\pi/2', '\pi'}));    
ylabel('Frequency (Hz)');
ylim(ylimits);
xticklabels({});
[~, sh] = scaleline(ax(2), 3600,'1 Hour' );
sh.FontSize = 10;
title('TFpeak Scatterplot');


% Plot SO power histogram
axes(ax(3))
imagesc(SOpow_cbins, freq_cbins, SOpow_mat');
axis xy;
colormap(ax(3), 'parula');
pow_clims = climscale([],[],false);
c = colorbar_noresize;
c.Label.String = {'Density', '(peaks/min in bin)'};
c.Label.Rotation = -90;
c.Label.VerticalAlignment = "bottom";
xlabel('SO Power (Normalized)');
ylabel('Frequency (Hz)');
ylim(ylimits);
title('SO Power Histogram');

% Plot SO phase histogram
axes(ax(4))
imagesc(SOphase_cbins, freq_cbins, SOphase_mat');
axis xy;
colormap(ax(4), 'magma');
climscale;
c = colorbar_noresize;
c.Label.String = {'Proportion'};
c.Label.Rotation = -90;
c.Label.VerticalAlignment = "bottom";
xlabel('SO Phase (radians)');
ylabel('Frequency (Hz)');
ylim(ylimits);
title('SO Phase Histogram');
xticks([-pi -pi/2 0 pi/2 pi])
xticklabels({'-\pi', '-\pi/2', '0', '\pi/2', '\pi'});




