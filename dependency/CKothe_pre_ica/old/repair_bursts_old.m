function signal = repair_bursts(signal,remove_quantile,window_len,pca_flagquant,pca_maxchannels)
% Repairs local peak artifacts (such as generated by muscle activity) by interpolating the subspace.
% Signal = repair_bursts(Signal,RemovedQuantile,WindowLength)
%
% This is an automated artifact rejection function that ensures that the data contains no events
% that have abnormally strong power; the subspaces on which those events occur are reconstructed 
% (interpolated) based on the rest of the EEG signal during these time periods.
%
% The way in which this is done is as follows: in a sliding window the PCA decomposition for the window 
% is computed; if there are large artifacts in this window, they will be captured quite reliably 
% by the largest few dimensions of the PCA. For each vector in the PCA eigenvector space it is checked
% whether the variance along the given direction is larger than some quantile threshold across the 
% entire data set (if it is in the uppermost quantile of the data, see RemovedQuantile parameter), 
% the vector it will be flagged as part of the bad subspace in this window). 
%
% Next, based on only the activity in the remaining (non-artifact) subspace of the observed data,
% the source activity of some latent pseudo/placeholder "sources" is computed (more later on these).
% Then, this restricted source activity estimate is back-projected onto all PCA dimensions, including
% the artifacts (thus, the formerly artifactual subspace are interpolated based on some conservative 
% brain-source activity estimates). The result is then rotated back from PCA space into channel space.
%
% The placeholder source model (i.e. mixing matrix) is computed on a very clean portion of the data
% to be maximally unaffected by burst activity.
%
% In:
%   Signal          : continuous data set, assumed to be appropriately high-passed (e.g. >0.5Hz or
%                     with a 0.5Hz - 2.0Hz transition band)
%
%   RemovedQuantile : upper quantile of the signal that should be flagged as "bad"; controls the
%                     aggressiveness of the filter (default: 0.1)
%
%   WindowLength    : length of the windows (in seconds) for which the power is computed, i.e. the 
%                     granularity of the measure; ideally short enough to reasonably isolate
%                     artifacts, but no shorter (for computational reasons) (default: 1)
%
%
%   --- rarely used parameters ---
%
%   PCACleanliness   : Rejetion quantile for PCA mixing model. This is the quantile of data windows
%                      that are rejected/ignored before a PCA correlation matrix is estimated; the 
%                      higher, the cleaner the PCA matrix will be (but the less data remains to 
%                      estimate it). (default: 0.25)
%
%   PCAForgiveChannels : Ignored channel fraction for PCA mixing model. If you know that some of 
%                        your channels are broken practically in the entire recording, this fraction 
%                        would need to cover them (plus some slack). This is the fraction of broken 
%                        channels that PCA will accept in the windows for which it computes covariances. 
%                        The lower this is, the less data will remain to estimate the covariance
%                        matrix but more channels will be estimated properly. (default: 0.1)
%
% Out:
%   Signal : data set with local peaks removed
%
% Examples:
%   % use the defaults
%   eeg = flt_repair_bursts(eeg);
%
%   % use a more aggressive threshold and different window length
%   eeg = flt_repair_bursts(eeg,0.3,0.75);
%
%   % use a different window length, and pass parameters by name
%   eeg = flt_repair_bursts('signal',eeg,'WindowLength',0.75);
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2010-07-10

if ~exist('remove_quantile','var') || isempty(remove_quantile) remove_quantile = 0.1; end
if ~exist('window_len','var') || isempty(window_len) window_len = 1; end
if ~exist('pca_flagquant','var') || isempty(pca_flagquant) pca_flagquant = 0.2; end;
if ~exist('pca_maxchannels','var') || isempty(pca_maxchannels) pca_maxchannels = 0.1; end;


% get data properties
[C,S] = size(signal.data); %#ok<*NODEF>
window_len = window_len*signal.srate;
wnd = 0:window_len-1;
wnd_weight = repmat(0.5*hann(length(wnd))',C,1);
offsets = 1 + floor(0:window_len/2:S-window_len);
W = length(offsets);

% find the cleanest section of the data and obtain a latent mixing matrix for this section
fprintf('First computing a latent-variable model. ');
cleanest = clean_windows(signal,pca_flagquant,[],pca_maxchannels);
sphere = 2.0*inv(sqrtm(double(cov(cleanest.data')))); %#ok<MINV>

% find the covariance distribution of the data (across windows)
X = signal.data;
XC = zeros(C,C,length(offsets));
for o=1:W
    S = X(:,offsets(o) + wnd).*wnd_weight;
    XC(:,:,o) = cov(S');
end
% and find the selected quantile of that
XX = sort(XC,3);
XQ = XX(:,:,floor(length(offsets)*(1-remove_quantile)));

Y = zeros(C,size(signal.data,2));
for o=1:W
    % get a weighted chunk of data 
    S = X(:,offsets(o) + wnd) .* wnd_weight;
    % get its principal components
    [V,D] = eig(cov(S'));
    
    % find a mask of extremal components in this eigenspace
    mask = diag(D) < diag(V'*XQ*V); mask(1:ceil(length(mask)/2)) = 1;    
    if ~all(mask)
        % have some rejections; first rotate the mixing matrix into the eigenspace
        mixing_eig = (V'/sphere);
        % generate a re-construction matrix with this subspace interpolated from the rest, in words:
        % 3. rotate back <-- 2. apply reconstruction in this space by first estimating activations of the latent mixture components with the artifact subspace ignored and then back-project from the components onto the PCA dimensions for this window  <-- 1. rotate data into eigenspace
        mixing_eig_trunc = mixing_eig; mixing_eig_trunc(~mask,:) = 0;
        reconstruct = V * (mixing_eig*pinv(mixing_eig_trunc)) * V';
        % now apply to the data segment
        Y(:,offsets(o) + wnd) = Y(:,offsets(o) + wnd) + reconstruct*S;
    else
        Y(:,offsets(o) + wnd) = Y(:,offsets(o) + wnd) + S;
    end
end

% write back
signal.data = Y;
signal.nbchan = size(signal.data,1);
