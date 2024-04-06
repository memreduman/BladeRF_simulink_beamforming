%function sdrqpsktx = sdrqpsktx
% Set simulation parameters

% Copyright 2011-2023 The MathWorks, Inc.
clear
%% General simulation parameters
sdrqpsktx.Rsym = 0.5e6;             % Symbol rate in Hertz
sdrqpsktx.ModulationOrder = 4;      % QPSK alphabet size
sdrqpsktx.Interpolation = 2;        % Interpolation factor
sdrqpsktx.Decimation = 1;           % Decimation factor
sdrqpsktx.Tsym = 1/sdrqpsktx.Rsym;  % Symbol time in sec
sdrqpsktx.Fs   = sdrqpsktx.Rsym * sdrqpsktx.Interpolation; % Sample rate

%% Frame Specifications
% [BarkerCode*2 | 'Hello world\n'];
sdrqpsktx.BarkerCode      = [+1 +1 +1 +1 +1 -1 -1 +1 +1 -1 +1 -1 +1];   % Bipolar Barker Code
sdrqpsktx.BarkerLength    = length(sdrqpsktx.BarkerCode);
sdrqpsktx.HeaderLength    = sdrqpsktx.BarkerLength * 2;                  % Duplicate 2 Barker codes to be as a header
sdrqpsktx.Message         = 'Hello world';
sdrqpsktx.MessageLength   = strlength(sdrqpsktx.Message) + 1;              % 'Hello world 000\n'...
sdrqpsktx.NumberOfMessage = 1;                                           % Number of messages in a frame
sdrqpsktx.PayloadLength   = sdrqpsktx.NumberOfMessage * sdrqpsktx.MessageLength * 7; % 7 bits per characters
sdrqpsktx.FrameSize       = (sdrqpsktx.HeaderLength + sdrqpsktx.PayloadLength) ...
    / log2(sdrqpsktx.ModulationOrder);                                    % Frame size in symbols
sdrqpsktx.FrameTime       = sdrqpsktx.Tsym*sdrqpsktx.FrameSize;

%% Tx parameters
sdrqpsktx.RolloffFactor     = 0.5;                                          % Rolloff Factor of Raised Cosine Filter
sdrqpsktx.ScramblerBase     = 2;
sdrqpsktx.ScramblerPolynomial           = [1 1 1 0 1];
sdrqpsktx.ScramblerInitialConditions    = [0 0 0 0];
sdrqpsktx.RaisedCosineFilterSpan = 10; % Filter span of Raised Cosine Tx Rx filters (in symbols)

%% Rx parameters
sdrqpskrx.DesiredPower                  = 2;            % AGC desired output power (in watts)
sdrqpskrx.AveragingLength               = 50;           % AGC averaging length
sdrqpskrx.MaxPowerGain                  = 60;           % AGC maximum output power gain
sdrqpskrx.MaximumFrequencyOffset        = 6e3;
% Look into model for details for details of PLL parameter choice. Refer equation 7.30 of "Digital Communications - A Discrete-Time Approach" by Michael Rice.
K = 1;
A = 1/sqrt(2);
sdrqpskrx.PhaseRecoveryLoopBandwidth    = 0.01;         % Normalized loop bandwidth for fine frequency compensation
sdrqpskrx.PhaseRecoveryDampingFactor    = 1;            % Damping Factor for fine frequency compensation
sdrqpskrx.TimingRecoveryLoopBandwidth   = 0.01;         % Normalized loop bandwidth for timing recovery
sdrqpskrx.TimingRecoveryDampingFactor   = 1;            % Damping Factor for timing recovery
% K_p for Timing Recovery PLL, determined by 2KA^2*2.7 (for binary PAM), 
% QPSK could be treated as two individual binary PAM, 
% 2.7 is for raised cosine filter with roll-off factor 0.5
sdrqpskrx.TimingErrorDetectorGain       = 2.7*2*K*A^2+2.7*2*K*A^2; 
sdrqpskrx.PreambleDetectionThreshold    = 0.8;            % Preamble detection threshold for Frame Synchronizer

%% Message generation
%msgSet = zeros(sdrqpsktx.NumberOfMessage * sdrqpsktx.MessageLength, 1); 
%msgCnt = 0;
%msgSet(msgCnt * sdrqpsktx.MessageLength + (1 : sdrqpsktx.MessageLength)) = ...
%        sprintf('%s %03d\n', sdrqpsktx.Message, msgCnt);
msgSet = sprintf('%s\n', sdrqpsktx.Message);
bits = reshape(dec2bin(msgSet, 7).'-'0',[],1);
%bits = de2bi(msgSet, 7, 'left-msb')';
sdrqpsktx.MessageBits = bits(:);

% For BER calculation masks
sdrqpskrx.BerMask = zeros(sdrqpsktx.NumberOfMessage * length(sdrqpsktx.Message) * 7, 1);
for i = 1 : sdrqpsktx.NumberOfMessage
   sdrqpskrx.BerMask( (i-1) * length(sdrqpsktx.Message) * 7 + ( 1: length(sdrqpsktx.Message) * 7) ) = ...
        (i-1) * sdrqpsktx.MessageLength * 7 + (1: length(sdrqpsktx.Message) * 7);
end

% Pluto transmitter&receiver parameters
sdrqpsktx.BladeRF_Frequency      = 915e6;
sdrqpsktx.BladeRF_Gain_Tx                 = 70;
sdrqpsktx.BladeRF_Gain_Rx                 = 70;
sdrqpsktx.BladeRF_SampleRate   = sdrqpsktx.Fs;
sdrqpsktx.BladeRF_FrameLength          = sdrqpsktx.Interpolation * sdrqpsktx.FrameSize;

% Simulation Parameters
sdrqpsktx.FrameTime = sdrqpsktx.BladeRF_FrameLength/sdrqpsktx.BladeRF_SampleRate;
sdrqpsktx.StopTime  = 1000;

% BladeRF USB settings
sdrqpsktx.BladeRF.stream.n_buffers = 256;
sdrqpsktx.BladeRF.stream.n_transfers = 8;
sdrqpsktx.BladeRF.stream.buffer_size = 1024*20;
sdrqpsktx.BladeRF.stream.timeout = 3500;
