%function qpsktxrx = qpsktxrx
% Set simulation parameters

% Copyright 2011-2023 The MathWorks, Inc.
clear
%% General simulation parameters
qpsktxrx.ModulationOrder = 4;      % QPSK alphabet size
qpsktxrx.Interpolation = 2;        % Interpolation factor
qpsktxrx.Decimation = 1;           % Decimation factor
qpsktxrx.Rsym = 5e4;               % Symbol rate in Hertz
qpsktxrx.Tsym = 1/qpsktxrx.Rsym;  % Symbol time in sec
qpsktxrx.Fs   = qpsktxrx.Rsym * qpsktxrx.Interpolation; % Sample rate
qpsktxrx.TotalFrame = 1000;        % Simulate 1000 frames in total

%% Frame Specifications
% [BarkerCode*2 | 'Hello world 000\n' | 'Hello world 001\n' ...];
qpsktxrx.BarkerCode      = [+1 +1 +1 +1 +1 -1 -1 +1 +1 -1 +1 -1 +1];     % Bipolar Barker Code
qpsktxrx.BarkerLength    = length(qpsktxrx.BarkerCode);
qpsktxrx.HeaderLength    = qpsktxrx.BarkerLength * 2;                   % Duplicate 2 Barker codes to be as a header
qpsktxrx.Message         = 'Hello world';
qpsktxrx.MessageLength   = strlength(qpsktxrx.Message) + 5;                % 'Hello world 000\n'...
qpsktxrx.NumberOfMessage = 20;                                           % Number of messages in a frame
qpsktxrx.PayloadLength   = qpsktxrx.NumberOfMessage * qpsktxrx.MessageLength * 7; % 7 bits per characters
qpsktxrx.FrameSize       = (qpsktxrx.HeaderLength + qpsktxrx.PayloadLength) ...
    / log2(qpsktxrx.ModulationOrder);                                    % Frame size in symbols
qpsktxrx.FrameTime       = qpsktxrx.Tsym*qpsktxrx.FrameSize;

%% Tx parameters
qpsktxrx.RolloffFactor     = 0.5;                                          % Rolloff Factor of Raised Cosine Filter
qpsktxrx.ScramblerBase     = 2;
qpsktxrx.ScramblerPolynomial           = [1 1 1 0 1];
qpsktxrx.ScramblerInitialConditions    = [0 0 0 0];
qpsktxrx.RaisedCosineFilterSpan = 10; % Filter span of Raised Cosine Tx Rx filters (in symbols)

%% Channel parameters
qpsktxrx.PhaseOffset       = 47;   % in degrees
qpsktxrx.EbNo              = 13;   % in dB
qpsktxrx.FrequencyOffset   = 5000; % Frequency offset introduced by channel impairments in Hertz
qpsktxrx.DelayType         = 'Triangle'; % select the type of delay for channel distortion

%% Rx parameters
qpsktxrx.DesiredPower                  = 2;            % AGC desired output power (in watts)
qpsktxrx.AveragingLength               = 50;           % AGC averaging length
qpsktxrx.MaxPowerGain                  = 20;           % AGC maximum output power gain
qpsktxrx.MaximumFrequencyOffset        = 6e3;
% Look into model for details for details of PLL parameter choice. Refer equation 7.30 of "Digital Communications - A Discrete-Time Approach" by Michael Rice.
K = 1;
A = 1/sqrt(2);
qpsktxrx.PhaseRecoveryLoopBandwidth    = 0.01;         % Normalized loop bandwidth for fine frequency compensation
qpsktxrx.PhaseRecoveryDampingFactor    = 1;            % Damping Factor for fine frequency compensation
qpsktxrx.TimingRecoveryLoopBandwidth   = 0.01;         % Normalized loop bandwidth for timing recovery
qpsktxrx.TimingRecoveryDampingFactor   = 1;            % Damping Factor for timing recovery
% K_p for Timing Recovery PLL, determined by 2KA^2*2.7 (for binary PAM), 
% QPSK could be treated as two individual binary PAM, 
% 2.7 is for raised cosine filter with roll-off factor 0.5
qpsktxrx.TimingErrorDetectorGain       = 2.7*2*K*A^2+2.7*2*K*A^2; 
qpsktxrx.PreambleDetectionThreshold    = 20;            % Preamble detection threshold for Frame Synchronizer

%% Message generation and BER calculation parameters
msgSet = zeros(100 * qpsktxrx.MessageLength, 1); 
for msgCnt = 0 : 99
    msgSet(msgCnt * qpsktxrx.MessageLength + (1 : qpsktxrx.MessageLength)) = ...
        sprintf('%s %03d\n', qpsktxrx.Message, msgCnt);
end
qpsktxrx.MessageBits = int2bit(msgSet, 7);

% For BER calculation masks
qpsktxrx.BerMask = zeros(qpsktxrx.NumberOfMessage * length(qpsktxrx.Message) * 7, 1);
for i = 1 : qpsktxrx.NumberOfMessage
    qpsktxrx.BerMask( (i-1) * length(qpsktxrx.Message) * 7 + ( 1: length(qpsktxrx.Message) * 7) ) = ...
        (i-1) * qpsktxrx.MessageLength * 7 + (1: length(qpsktxrx.Message) * 7);
end
