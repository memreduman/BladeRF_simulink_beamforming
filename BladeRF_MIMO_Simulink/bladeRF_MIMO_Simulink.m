% This class implements a bladeRF MATLAB System Simulink block.
%
% The bladeRF_Simulink block interfaces with a single bladeRF device and is
% capable of utilizing both the transmit and receive paths on the device. The
% block properties may be used to enable and use RX, TX, or both.
%
% To use this block, place a "MATLAB System" block in your Simulink Model and
% specify "bladeRF_Simulink" for the system object name.
%
% Next, configure the device by double clicking on the block. Here, a few
% groups of settings are presented:
%  * Device             Device selection and device-wide settings
%  * RX Configuration   RX-specific settings
%  * TX Configuration   TX-specific settings
%  * Miscellaneous      Other library-specific options
%
% Currently only "Interpreted Execution" is supported. Be sure to select
% this in the first tab.
%
% In the "Device" tab, the "Device Specification String" allows one to specify
% which device to use if multiple bladeRFs are connected.  For example, to use
% a device with a serial number starting with a3f..., a valid device
% specification string would be:
%
%           "*:serial=a3f"
%
% Alternatively, one can specify the "Nth" device if the block<->device
% assignments do not matter. For two devices, one could use:
%           "*:instance=0" and "*:instance=1"
%
% If left blank, this string will select the first available device.
%
% To enable the receive output port, check the "Enable Receiver" checkbox in
% the "RX Configuration" tab.  Similarly to enable the transmit input port,
% check the "Enable Transmitter" checkbox in the "TX Configuration" tab.
%
% See also: bladeRF

% Copyright (c) 2015 Nuand LLC
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
% THE SOFTWARE.
%

classdef bladeRF_MIMO_Simulink < matlab.System & ...
                            matlab.system.mixin.Propagates & ...
                            matlab.system.mixin.CustomIcon
    %% Properties
    properties
        verbosity           = 'Info'    % libbladeRF verbosity

        rx_frequency        = 915e6;    % Channel 1 Frequency (Hz)
        rx_gain             = 60;   	% Channel 1 RX Gain [-10, 90]
        rx_agc              = 'SLOW';   % Channel 1 AGC mode
		
		rx2_frequency        = 915e6;    % Channel 2 Frequency (Hz)
        rx2_gain             = 60;       % Channel 2 RX Gain [-10, 90]
        rx2_agc              = 'SLOW'; % Channel 2 AGC mode

        tx_frequency        = 915e6;    % Channel 1 Frequency (Hz)
        tx_gain             = 60;  % Channel 1 TX Gain [-10, 90]
		
		tx2_frequency        = 915e6;    % Channel 2 Frequency (Hz)
        tx2_gain             = 60;  % Channel 2 TX Gain [-10, 90]
    end

    properties(Nontunable)
        device_string       = '';       % Device specification string
		fpga_string       = '';			% Define full-path for FPGA file
        loopback_mode       = 'None'    % Active loopback mode

        rx_bandwidth        = '1.5';    % Channel 1 LPF Bandwidth (MHz)
        rx_samplerate       = 3e6;      % Channel 1 Sample rate (and RX-MIMO Sample rate)
		
		rx2_bandwidth        = '1.5';    % Channel 2 LPF Bandwidth (MHz)
        rx2_samplerate       = 3e6;      % Channel 2 Sample rate (will be ignored when both channels are active)
		
        rx_num_buffers      = 64;       % Number of stream buffers to use
        rx_num_transfers    = 16;       % Number of USB transfers to use
        rx_buf_size         = 16384;    % Size of each stream buffer, in samples (must be multiple of 1024)
        rx_step_size        = 16384;    % Number of samples to RX during each simulation step
        rx_timeout_ms       = 5000;     % Stream timeout (ms)

        tx_bandwidth        = '1.5';    % Channel 1 LPF Bandwidth (MHz)
        tx_samplerate       = 3e6;      % Channel 1 Sample rate
		
		tx2_bandwidth        = '1.5';    % Channel 2 LPF Bandwidth (MHz)
        tx2_samplerate       = 3e6;      % Channel 2 Sample rate
		
        tx_num_buffers      = 64;       % Number of stream buffers to use
        tx_num_transfers    = 16;       % Number of USB transfers to use
        tx_buf_size         = 16384;    % Size of each stream buffer, in samples (must be multiple of 1024)
        tx_step_size        = 16384;  	% Number of samples to TX during each simulation step
        tx_timeout_ms       = 5000;     % Stream timeout (ms)
		
    end

    properties(Logical, Nontunable)
        enable_rx           = true;     % Enable Receiver
        enable_rx_biastee   = false;    % Enable RX Biastee
        enable_overrun      = false;    % Enable Overrun output (available for both channels)
        enable_tx           = false;    % Enable Transmitter
        enable_tx_biastee   = false;    % Enable TX Biastee
        enable_underrun     = false;    % Enable Underrun output (for future use)
        xb200               = false     % Enable use of XB-200 (must be attached)
		
		enable_rx2           = false;     % Enable Receiver
        enable_rx2_biastee   = false;    % Enable RX Biastee

        enable_tx2           = false;     % Enable Transmitter
        enable_tx2_biastee   = false;    % Enable TX Biastee

		enable_rx_mimo = false;
		enable_tx_mimo = false;
    end

    properties(Hidden, Transient)
        rx_bandwidthSet = matlab.system.StringSet({ ...
            '1.5',  '1.75', '2.5',  '2.75',  ...
            '3',    '3.84', '5',    '5.5',   ...
            '6',    '7',    '8.75', '10',    ...
            '12',   '14',   '20',   '28',    ...
            '30',   '32',   '34',   '36',    ...
            '38',   '40',   '42',   '44',    ...
            '46',   '48',   '50',   '52',    ...
            '54',   '56',   '58',   '60',    ...
            '62',   '64',   '64.11'  ...
        });
		
        rx2_bandwidthSet = matlab.system.StringSet({ ...
            '1.5',  '1.75', '2.5',  '2.75',  ...
            '3',    '3.84', '5',    '5.5',   ...
            '6',    '7',    '8.75', '10',    ...
            '12',   '14',   '20',   '28',    ...
            '30',   '32',   '34',   '36',    ...
            '38',   '40',   '42',   '44',    ...
            '46',   '48',   '50',   '52',    ...
            '54',   '56',   '58',   '60',    ...
            '62',   '64',   '64.11'  ...
        });
		
        tx_bandwidthSet = matlab.system.StringSet({ ...
            '1.5',  '1.75', '2.5',  '2.75',  ...
            '3',    '3.84', '5',    '5.5',   ...
            '6',    '7',    '8.75', '10',    ...
            '12',   '14',   '20',   '28',    ...
            '30',   '32',   '34',   '36',    ...
            '38',   '40',   '42',   '44',    ...
            '46',   '48',   '50',   '52',    ...
            '54',   '56',   '58',   '60',    ...
            '62',   '64',   '64.11'  ...
        });
		
        tx2_bandwidthSet = matlab.system.StringSet({ ...
            '1.5',  '1.75', '2.5',  '2.75',  ...
            '3',    '3.84', '5',    '5.5',   ...
            '6',    '7',    '8.75', '10',    ...
            '12',   '14',   '20',   '28',    ...
            '30',   '32',   '34',   '36',    ...
            '38',   '40',   '42',   '44',    ...
            '46',   '48',   '50',   '52',    ...
            '54',   '56',   '58',   '60',    ...
            '62',   '64',   '64.11'  ...
        });
		
        rx_agcSet = matlab.system.StringSet({
            'AUTO', 'MANUAL', ...
            'SLOW', 'FAST', 'HYBRID' ...
        });
		
		rx2_agcSet = matlab.system.StringSet({
            'AUTO', 'MANUAL', ...
            'SLOW', 'FAST', 'HYBRID' ...
        });

        loopback_modeSet = matlab.system.StringSet({
            'None', ...
            'BB_TXLPF_RXVGA2', 'BB_TXVGA1_RXVGA2', 'BB_TXLPF_RXLPF', ...
            'BB_TXVGA1_RXLPF', 'RF_LNA1', 'RF_LNA2', 'RF_LNA3', ...
            'Firmware'
        });

        verbositySet = matlab.system.StringSet({
            'Verbose', 'Debug', 'Info', 'Warning', 'Critical', 'Silent' ...
        });
    end

    properties (Access = private)
        device = []

        % Cache previously set tunable values to avoid querying the device
        % for all properties when only one changes.
        curr_rx_frequency
        curr_rx_lna
        curr_rx_vga1
        curr_rx_vga2
        curr_rx_gain
        curr_rx_agc
        curr_rx_biastee
        curr_tx_frequency
        curr_tx_vga1
        curr_tx_vga2
        curr_tx_gain
        curr_tx_biastee
		
		curr_rx2_frequency
        curr_rx2_gain
        curr_rx2_agc
		
        curr_rx2_biastee
        curr_tx2_frequency
        curr_tx2_gain
        curr_tx2_biastee
		
		%% For MIMO
		curr_tx_frequency_arr
		curr_tx_biastee_arr
		curr_tx_gain_arr

		curr_rx_frequency_arr
		curr_rx_biastee_arr
		curr_rx_agc_arr
		curr_rx_gain_arr
		
		rx_samples2
		rx_overrun2
		rx_samples_channel1
		rx_samples_channel2

    end

    %% Static Methods
    methods (Static, Access = protected)
        function groups = getPropertyGroupsImpl
            device_section_group = matlab.system.display.SectionGroup(...
                'Title', 'Device', ...
                'PropertyList', {'device_string','fpga_string' , 'loopback_mode', 'xb200' } ...
            );

            rx_gain_section = matlab.system.display.Section(...
                'Title', 'Gain', ...
                'PropertyList', { 'rx_gain', 'enable_rx_biastee', 'rx_agc'  } ...
            );

            rx_stream_section = matlab.system.display.Section(...
                'Title', 'Stream', 'Description','This settings will be applied for both channels', ...
                'PropertyList', {'rx_num_buffers', 'rx_num_transfers', 'rx_buf_size', 'rx_timeout_ms', 'rx_step_size', } ...
            );

            rx_section_group = matlab.system.display.SectionGroup(...
                'Title', 'RX Configuration', ...
                'PropertyList', { 'enable_rx', 'enable_overrun', 'rx_frequency', 'rx_samplerate', 'rx_bandwidth' }, ...
                'Sections', [ rx_gain_section, rx_stream_section ] ...
            );
			
			rx2_gain_section = matlab.system.display.Section(...
                'Title', 'Gain', ...
                'PropertyList', { 'rx2_gain', 'enable_rx2_biastee', 'rx2_agc'  } ...
            );
			
            rx2_section_group = matlab.system.display.SectionGroup(...
                'Title', 'RX2 Configuration', ...
                'PropertyList', { 'enable_rx2', 'rx2_frequency', 'rx2_samplerate', 'rx2_bandwidth' }, ...
                'Sections', [ rx2_gain_section ] ...
            );
			
            tx_gain_section = matlab.system.display.Section(...
                'Title', 'Gain', ...
                'PropertyList', { 'tx_gain', 'enable_tx_biastee' } ...
            );

            tx_stream_section = matlab.system.display.Section(...
                'Title', 'Stream', 'Description','This settings will be applied for both channels', ...
                'PropertyList', {'tx_num_buffers', 'tx_num_transfers', 'tx_buf_size', 'tx_timeout_ms', 'tx_step_size', } ...
            );

            tx_section_group = matlab.system.display.SectionGroup(...
                'Title', 'TX Configuration', ...
                'PropertyList', { 'enable_tx', 'enable_underrun', 'tx_frequency', 'tx_samplerate', 'tx_bandwidth' }, ...
                'Sections', [ tx_gain_section, tx_stream_section ] ...
            );
			
			tx2_gain_section = matlab.system.display.Section(...
                'Title', 'Gain', ...
                'PropertyList', { 'tx2_gain', 'enable_tx2_biastee' } ...
            );

            tx2_section_group = matlab.system.display.SectionGroup(...
                'Title', 'TX2 Configuration', ...
                'PropertyList', { 'enable_tx2', 'tx2_frequency', 'tx2_samplerate', 'tx2_bandwidth' }, ...
                'Sections', [ tx2_gain_section ] ...
            );

            misc_section_group = matlab.system.display.SectionGroup(...
                'Title', 'Miscellaneous', ...
                'PropertyList', {'verbosity'} ...
            );

            groups = [ device_section_group, rx_section_group, rx2_section_group, tx_section_group,tx2_section_group, misc_section_group ];
        end

        function header = getHeaderImpl
            text = 'This block provides access to a Nuand bladeRF device via libbladeRF MATLAB bindings.';
            header = matlab.system.display.Header('bladeRF_Simulink', ...
                'Title', 'bladeRF', 'Text',  text ...
            );
        end
    end

    methods (Access = protected)
        %% Output setup
        function count = getNumOutputsImpl(obj) %% BURASI BİTTİ
		
            if obj.enable_rx == true 
                count = 1;
            else
                count = 0;
            end
			
            if obj.enable_rx2 == true 
                    count = count + 1;
            else
                count = count;
            end
			
			if obj.enable_overrun == true && ( obj.enable_rx2 == true || obj.enable_rx == true )
                count = count + 1;
			end


            if obj.enable_tx == true && obj.enable_underrun == true
                count = count + 1;
            end
        end

        function varargout = getOutputNamesImpl(obj) %% BURASI BİTTİ
		
            if obj.enable_rx == true
                varargout{1} = 'RX1 Samples';
                n = 2;	
            else
                n = 1;
            end
			
			if obj.enable_rx2 == true
				varargout{n} = 'RX2 Samples';
				n = n + 1;
			end
			
            if obj.enable_overrun == true && ( obj.enable_rx2 == true || obj.enable_rx == true )
                varargout{n} = 'RX Overrun';
                n = n + 1;
            end					
			

            if obj.enable_tx == true && obj.enable_underrun == true
                varargout{n} = 'TX Underrun';
            end
        end

        function varargout = getOutputDataTypeImpl(obj) %% BURASI BİTTİ
            if obj.enable_rx == true
                varargout{1} = 'double';    % RX Samples
                n = 2;
            else
                n = 1;
            end
			
			if obj.enable_rx2 == true
				varargout{n} = 'double';    % RX2 Samples
				n = n + 1;
			end
			
			if obj.enable_overrun == true && ( obj.enable_rx2 == true || obj.enable_rx == true )
                varargout{n} = 'logical';   % RX Overrun
				n = n + 1;
			end
			
			
            if obj.enable_tx == true && obj.enable_underrun == true
                varargout{n} = 'logical';   % TX Underrun
            end
        end

        function varargout = getOutputSizeImpl(obj) %% BURASI BİTTİ

            if obj.enable_rx == true
                varargout{1} = [obj.rx_step_size 1];  % RX Samples
                n = 2;
            else
                n = 1;
            end
			
			if obj.enable_rx2 == true
				varargout{n} = [obj.rx_step_size 1];  % RX2 Samples
				n = n + 1;
			end
			
            if obj.enable_overrun == true && ( obj.enable_rx2 == true || obj.enable_rx == true )
                varargout{n} = [1 1]; % RX Overrun
                n = n + 1;
            end			
			
            if obj.enable_tx == true && obj.enable_underrun == true
                varargout{n} = [1]; % TX Underrun
            end
        end

        function varargout = isOutputComplexImpl(obj) %% BURASI BİTTİ
            if obj.enable_rx == true
                varargout{1} = true;    % RX Samples
                n = 2;
            else
                n = 1;
            end

			if obj.enable_rx2 == true
				varargout{n} = true; % RX2 Samples
				n = n + 1;
			end
			
			if obj.enable_overrun == true && ( obj.enable_rx2 == true || obj.enable_rx == true )
                varargout{n} = false;   % RX Overrun
                n = n + 1;
            end		

            if obj.enable_tx == true && obj.enable_underrun == true
                varargout{n} = false;   % TX Underrun
            end
        end

        function varargout  = isOutputFixedSizeImpl(obj) %% BURASI BİTTİ
            if obj.enable_rx == true
                varargout{1} = true;    % RX Samples
                n = 2;
            else
                n = 1;
            end
			
			if obj.enable_rx2 == true
				varargout{n} = true; % RX2 Samples
				n = n + 1;
			end
			
			if obj.enable_overrun == true && ( obj.enable_rx2 == true || obj.enable_rx == true )
				varargout{n} = true;    % RX Overrun
				n = n + 1;
            end	
			
            if obj.enable_tx == true && obj.enable_underrun == true
                varargout{n} = true;    % TX Underrun
            end
        end

        %% Input setup
        function count = getNumInputsImpl(obj) %% BURASI BİTTİ
            if obj.enable_tx == true
                count = 1;
            else
                count = 0;
            end
			
			if obj.enable_tx2 == true
				count = count + 1;
			else
				count=count;
			end
			
        end

        function varargout = getInputNamesImpl(obj) %% BURASI BİTTİ
			
            if obj.enable_tx == true
                varargout{1} = 'TX1 Samples';
				n = 2;
			else
				n = 1;
			end
			
			if obj.enable_tx2 == true
				varargout{n} = 'TX2 Samples';
			end
			
        end

        %% Property and Execution Handlers
        function icon = getIconImpl(~) %% BURASI BİTTİ
            icon = sprintf('Nuand\nbladeRF 2.0\nMIMO');
        end

        function setupImpl(obj) %% BURASI BİTTİ
            %% Library setup
            bladeRF_MIMO.log_level(obj.verbosity);

            %% Device setup
            if obj.xb200 == true
                xb = 'XB200';
            else
                xb = [];
            end
			%% MIMO settings
			% RX
			if obj.enable_rx == true && obj.enable_rx2 == true
				%obj.device.enable_rx_mimo = true; % Active the mimo settings for RX
				obj.enable_rx_mimo = true;
			else
				obj.enable_rx_mimo = false;
			end
			% TX
			if obj.enable_tx == true && obj.enable_tx2 == true
				%obj.device.enable_tx_mimo = true; % Active the mimo settings for TX
				obj.enable_tx_mimo = true;
			else
				obj.enable_tx_mimo = false;
			end
	
			%warning('enable_rx_mimo= %s\nenable_tx_mimo= %s\nenable_rx2= %s\nenable_tx2= %s\nenable_rx= %s\nenable_tx= %s',...
			%		mat2str(obj.enable_rx_mimo),...
			%		mat2str(obj.enable_tx_mimo),...
			%		mat2str(obj.enable_rx2),...
			%		mat2str(obj.enable_tx2),...
			%		mat2str(obj.enable_rx),...
			%		mat2str(obj.enable_tx));			
			%
			
            obj.device = bladeRF_MIMO(obj.device_string, obj.fpga_string, xb,obj.enable_rx,obj.enable_tx,obj.enable_rx2,obj.enable_tx2,obj.enable_rx_mimo,obj.enable_tx_mimo);  % bladeRF_MIMO(devstring, fpga_bitstream, xb,enable_rx2,enable_tx2,enable_rx_mimo,enable_tx_mimo)
            obj.device.loopback = obj.loopback_mode;

            %% RX - General Setup
			
            obj.device.rx.config.num_buffers   = obj.rx_num_buffers;
            obj.device.rx.config.buffer_size   = obj.rx_buf_size;
            obj.device.rx.config.num_transfers = obj.rx_num_transfers;
            obj.device.rx.config.timeout_ms    = obj.rx_timeout_ms;
			
			% RX2 - Setup
			if obj.enable_rx2 == true && obj.enable_rx_mimo == false
				warning("RX2 Parameters are set !");
				obj.device.rx.frequency  = obj.rx2_frequency;
				obj.curr_rx2_frequency    = obj.device.rx.frequency;
			
				obj.device.rx.samplerate = obj.rx2_samplerate;
			
				obj.device.rx.bandwidth  = str2double(obj.rx2_bandwidth) * 1e6;
			
				obj.device.rx.biastee    = obj.enable_rx2_biastee;
				obj.curr_rx2_biastee      = obj.device.rx.biastee;
			
				obj.device.rx.agc      = obj.rx2_agc;
				obj.curr_rx2_agc          = obj.device.rx.agc;
			
				if strcmpi(obj.curr_rx2_agc, 'manual')
					obj.device.rx.gain      = obj.rx2_gain;
					obj.curr_rx2_gain         = obj.device.rx.gain;
				else
				warning([ 'Cannot set RX2 gain because AGC is set to ' (obj.curr_rx2_agc) ' mode']);
				end
				
			elseif obj.enable_rx == true && obj.enable_rx_mimo == false
			% RX1 - Setup
				warning("RX1 Parameters are set !");
				obj.device.rx.frequency  = obj.rx_frequency;
				obj.curr_rx_frequency    = obj.device.rx.frequency;

				obj.device.rx.samplerate = obj.rx_samplerate;
			
				obj.device.rx.bandwidth  = str2double(obj.rx_bandwidth) * 1e6;

				obj.device.rx.biastee    = obj.enable_rx_biastee;
			
				obj.curr_rx_biastee      = obj.device.rx.biastee;
			
				obj.device.rx.agc        = obj.rx_agc;
			
				obj.curr_rx_agc          = obj.device.rx.agc;
			
				if strcmpi(obj.curr_rx_agc, 'manual')
					obj.device.rx.gain       = obj.rx_gain;
					obj.curr_rx_gain         = obj.device.rx.gain;
            
					warning([ 'Cannot set RX gain because AGC is set to ' (obj.curr_rx_agc) ' mode'])
				end
			elseif obj.enable_rx_mimo == true
			%RX MIMO - Setup
				warning("RX_MIMO Parameters are set !");
				obj.device.rx.frequency  = [obj.rx_frequency,obj.rx2_frequency];
				obj.curr_rx_frequency_arr = obj.device.rx.frequency;
				obj.curr_rx_frequency = obj.curr_rx_frequency_arr(1);
				obj.curr_rx2_frequency = obj.curr_rx_frequency_arr(2);
				
				obj.device.rx.samplerate = [obj.rx_samplerate,obj.rx2_samplerate];
			
				obj.device.rx.bandwidth  = [str2double(obj.rx_bandwidth) * 1e6,str2double(obj.rx2_bandwidth) * 1e6];

				obj.device.rx.biastee    = [obj.enable_rx_biastee,obj.enable_rx2_biastee];
				obj.curr_rx_biastee_arr  = obj.device.rx.biastee;
				obj.curr_rx_biastee =  obj.curr_rx_biastee_arr(1);
				obj.curr_rx2_biastee = obj.curr_rx_biastee_arr(2);
				
				obj.device.rx.agc        = {obj.rx_agc,obj.rx2_agc};
				obj.curr_rx_agc_arr      = obj.device.rx.agc;
			    obj.curr_rx_agc      = char(obj.curr_rx_agc_arr(1));
				obj.curr_rx2_agc      = char(obj.curr_rx_agc_arr(2));
				
				if strcmpi(obj.curr_rx_agc, 'manual') == true && strcmpi(obj.curr_rx2_agc, 'manual') == true
					obj.device.rx.gain       = [obj.rx_gain,obj.rx2_gain];
					obj.curr_rx_gain_arr         = obj.device.rx.gain;
					obj.curr_rx_gain = obj.curr_rx_gain_arr(1);
					obj.curr_rx2_gain = obj.curr_rx_gain_arr(2);
				else
					warning([ 'Cannot set RX1 gain because AGC is set to ' (obj.curr_rx_agc) ' mode'])
					warning([ 'Cannot set RX2 gain because AGC is set to ' (obj.curr_rx2_agc) ' mode'])
				end
			end

            %% TX - General Setup
			
			obj.device.tx.config.num_buffers   = obj.tx_num_buffers;
            obj.device.tx.config.buffer_size   = obj.tx_buf_size;
            obj.device.tx.config.num_transfers = obj.tx_num_transfers;
            obj.device.tx.config.timeout_ms    = obj.tx_timeout_ms;
			
			% TX2 Setup
			if obj.enable_tx2 == true && obj.enable_tx_mimo == false
				warning("TX2 Parameters are set !");
				obj.device.tx.samplerate = obj.tx2_samplerate;
				obj.device.tx.bandwidth  = str2double(obj.tx2_bandwidth) * 1e6;

				obj.device.tx.frequency  = obj.tx2_frequency;
				obj.curr_tx2_frequency    = obj.device.tx.frequency;

				obj.device.tx.biastee    = obj.enable_tx2_biastee;
				obj.curr_tx2_biastee      = obj.device.tx.biastee;

				obj.device.tx.gain       = obj.tx2_gain;
				obj.curr_tx2_gain         = obj.device.tx.gain;
			
			% TX1 Setup
			elseif obj.enable_tx == true && obj.enable_tx_mimo == false
				warning("TX1 Parameters are set !");
				obj.device.tx.samplerate = obj.tx_samplerate;
				obj.device.tx.bandwidth  = str2double(obj.tx_bandwidth) * 1e6;

				obj.device.tx.frequency  = obj.tx_frequency;
				obj.curr_tx_frequency    = obj.device.tx.frequency;

				obj.device.tx.biastee    = obj.enable_tx_biastee;
				obj.curr_tx_biastee      = obj.device.tx.biastee;

				obj.device.tx.gain       = obj.tx_gain;
				obj.curr_tx_gain         = obj.device.tx.gain;
			elseif obj.enable_tx_mimo == true
				warning("TX_MIMO Parameters are set !");
				obj.device.tx.samplerate = [obj.tx_samplerate,obj.tx2_samplerate];
				obj.device.tx.bandwidth  = [str2double(obj.tx_bandwidth) * 1e6, str2double(obj.tx2_bandwidth) * 1e6];

				obj.device.tx.frequency  = [obj.tx_frequency,obj.tx2_frequency];
				obj.curr_tx_frequency_arr    = obj.device.tx.frequency;
				obj.curr_tx_frequency = obj.curr_tx_frequency_arr(1);
				obj.curr_tx2_frequency = obj.curr_tx_frequency_arr(2);
				
				obj.device.tx.biastee    = [obj.enable_tx_biastee,obj.enable_tx2_biastee];
				obj.curr_tx_biastee_arr  = obj.device.tx.biastee;
				obj.curr_tx_biastee =  obj.curr_tx_biastee_arr(1);
				obj.curr_tx2_biastee = obj.curr_tx_biastee_arr(2);

				obj.device.tx.gain    = [obj.tx_gain,obj.tx2_gain];
				obj.curr_tx_gain_arr  = obj.device.tx.gain;
				obj.curr_tx_gain 	  = obj.curr_tx_gain_arr(1);
				obj.curr_tx2_gain     = obj.curr_tx_gain_arr(2);
			end
        end

        function releaseImpl(obj) %% BURASI BİTTİ
            delete(obj.device);
        end

        function resetImpl(obj) %% BURASI BİTTİ
			if obj.enable_rx == true || obj.enable_rx2 == true
				obj.device.rx.stop();
			end
			if obj.enable_tx == true || obj.enable_tx2 == true
				obj.device.tx.stop();
			end
            
        end

        % Perform a read of received samples and an 'overrun' array that denotes whether
        % the associated samples is invalid due to a detected overrun.
		
        function varargout = stepImpl(obj, varargin) %% BURASI BİTTİ
            varargout = {};	

			% If RX MIMO is actived
			if obj.enable_rx_mimo == true
				if obj.device.rx.running == false
                    obj.device.rx.start(); % Start RX module
				end	
				
				%obj.rx_samples2 = double(zeros(obj.rx_step_size, 2)); 
				[rx2_samples, ~, ~, rx_overrun] = obj.device.receive(obj.rx_step_size);
				%obj.rx_timeout_ms
				
				%obj.rx_samples_channel1 = double(zeros(obj.rx_step_size, 1));
				%obj.rx_samples_channel2 = double(zeros(obj.rx_step_size, 1));
				
				%obj.rx_samples_channel1 = obj.rx_samples2(:, 1); % take received sample [ rx_step_size , 2 ] matrix and split
				%obj.rx_samples_channel2 = obj.rx_samples2(:, 2);
				
				%obj.rx_samples_channel1 = obj.rx_samples2(1:obj.rx_step_size); % take received sample [ rx_step_size , 2 ] matrix and split
				%obj.rx_samples_channel2 = obj.rx_samples2(obj.rx_step_size+1:end);	
						

				varargout{1} = rx2_samples(:, 1); % Split data to the channels
				varargout{2} = rx2_samples(:, 2); % Split data to the channels						
			
				%varargout{1} = obj.rx_samples_channel1; % Split data to the channels
				%varargout{2} = obj.rx_samples_channel2; % Split data to the channels
				
				varargout{3} = rx_overrun;
				
				
				out_idx = 4;
			else
				out_idx = 1;
            end
				
			% If TX MIMO is actived
			if obj.enable_tx_mimo == true
				if obj.device.tx.running == false
                    obj.device.tx.start(); % Start RX module
				end
				
				obj.device.transmit([varargin{1},varargin{2}]); % Take two input and transmit

                % Detecting TX Underrun is not yet supported by libbladeRF.
                % This is for future use.
				out_idx = 3;
                varargout{out_idx} = false;
			else
				out_idx = 1;
            end
				
			
			% If only 1 RX channel is enabled
			if (obj.enable_rx == true || obj.enable_rx2 == true) && obj.enable_rx_mimo == false
                if obj.device.rx.running == false
                    obj.device.rx.start();
                end

                [rx_samples, ~, ~, rx_overrun] = obj.device.receive(obj.rx_step_size);
				
                varargout{1} = rx_samples;
                varargout{2} = rx_overrun;
                out_idx = 3;
            else
                out_idx = 1;
            end
			
			% If only 1 TX channel is enabled
			if (obj.enable_tx == true || obj.enable_tx2 == true) && obj.enable_tx_mimo == false 
                if obj.device.tx.running == false
                    obj.device.tx.start();
					warning("TX is started !!!");
                end

                obj.device.transmit(varargin{1});

                % Detecting TX Underrun is not yet supported by libbladeRF.
                % This is for future use.
                varargout{out_idx} = false;
            end
        end

        function processTunedPropertiesImpl(obj) %% gereksiz değerleri çıkar

            %% RX Properties
            if isChangedProperty(obj, 'rx_frequency') && obj.rx_frequency ~= obj.curr_rx_frequency
                obj.device.rx.frequency = obj.rx_frequency;
                %obj.rx_frequency = obj.device.rx.frequency;

                obj.curr_rx_frequency   = obj.device.rx.frequency;
                %disp('Updated RX frequency');
            end

            if isChangedProperty(obj, 'rx_gain') && obj.rx_gain ~= obj.curr_rx_gain
                obj.device.rx.gain = obj.rx_gain;
                %obj.rx_gain = obj.device.rx.gain;

                obj.curr_rx_gain = obj.device.rx.gain;
                %disp('Updated RX gain');
            end

            if isChangedProperty(obj, 'rx_agc') && obj.rx_agc ~= obj.curr_rx_agc
                obj.device.rx.agc = obj.rx_agc;
                %obj.rx_agc = obj.device.rx.agc;

                obj.curr_rx_agc   = obj.device.rx.agc;
                %disp('Updated RX AGC gain');
            end

            %% TX Properties
            if isChangedProperty(obj, 'tx_frequency') && obj.tx_frequency ~= obj.curr_tx_frequency
                obj.device.tx.frequency = obj.tx_frequency;
                obj.curr_tx_frequency   = obj.device.rx.frequency;
                %disp('Updated TX frequency');
            end

            if isChangedProperty(obj, 'tx_gain') && obj.tx_gain ~= obj.curr_tx_gain
                obj.device.tx.gain = obj.tx_gain;
                obj.curr_tx_gain   = obj.device.tx.gain;
                %disp('Updated TX gain');
            end
			
			%% RX2 Properties
            if isChangedProperty(obj, 'rx2_frequency') && obj.rx2_frequency ~= obj.curr_rx2_frequency
                obj.device.rx.frequency = obj.rx2_frequency;
                %obj.rx_frequency = obj.device.rx.frequency;

                obj.curr_rx2_frequency   = obj.device.rx.frequency;
                %disp('Updated RX2 frequency');
            end

            if isChangedProperty(obj, 'rx2_gain') && obj.rx2_gain ~= obj.curr_rx2_gain
                obj.device.rx.gain = obj.rx2_gain;
                %obj.rx_gain = obj.device.rx.gain;

                obj.curr_rx2_gain = obj.device.rx.gain;
                %disp('Updated RX2 gain');
            end

            if isChangedProperty(obj, 'rx2_agc') && obj.rx2_agc ~= obj.curr_rx2_agc
                obj.device.rx.agc = obj.rx2_agc;
                %obj.rx_agc = obj.device.rx.agc;

                obj.curr_rx2_agc   = obj.device.rx.agc;
                %disp('Updated RX AGC gain');
            end

            %% TX2 Properties
            if isChangedProperty(obj, 'tx2_frequency') && obj.tx2_frequency ~= obj.curr_tx2_frequency
                obj.device.tx.frequency = obj.tx2_frequency;
                obj.curr_tx2_frequency   = obj.device.rx.frequency;
                %disp('Updated TX frequency');
            end

            if isChangedProperty(obj, 'tx2_gain') && obj.tx2_gain ~= obj.curr_tx2_gain
                obj.device.tx.gain = obj.tx2_gain;
                obj.curr_tx2_gain   = obj.device.tx.gain;
                %disp('Updated TX gain');
            end
			
			
        end

        function validatePropertiesImpl(obj) %% MIMO ya göre değerlerin ayarlanması lazım
            if obj.enable_rx == false && obj.enable_tx == false && obj.enable_rx2 == false && obj.enable_tx2 == false
                warning('Neither bladeRF RX1-2 or TX1-2 is enabled. One or both should be enabled.');
            end

            if isempty(obj.device)
                tx_min_freq = 0;
                tx_max_freq = 0;
                tx_min_sampling = 0;
                tx_max_sampling = 0;

                rx_min_freq = 0;
                rx_max_freq = 0;
                rx_min_sampling = 0;
                rx_max_sampling = 0;
				
                return
            else
                tx_min_freq = obj.device.tx.min_frequency;
                tx_max_freq = obj.device.tx.max_frequency;
                tx_min_sampling = obj.device.tx.min_sampling;
                tx_max_sampling = obj.device.tx.max_sampling;

                rx_min_freq = obj.device.rx.min_frequency;
                rx_max_freq = obj.device.rx.max_frequency;
                rx_min_sampling = obj.device.rx.min_sampling;
                rx_max_sampling = obj.device.rx.max_sampling;
            end

            %% Validate RX properties
            if obj.rx_num_buffers < 1
                error('rx_num_buffers must be > 0.');
            end

            if obj.rx_num_transfers >= obj.rx_num_buffers
                error('rx_num_transfers must be < rx_num_buffers.');
            end

            if obj.rx_buf_size < 1024 || mod(obj.rx_buf_size, 1024) ~= 0
                error('rx_buf_size must be a multiple of 1024.');
            end

            if obj.rx_timeout_ms < 0
                error('rx_timeout_ms must be >= 0.');
            end

            if obj.rx_step_size <= 0
                error('rx_step_size must be > 0.');
            end

            if obj.rx_samplerate < rx_min_sampling || obj.rx2_samplerate < rx_min_sampling
                error(['rx_samplerate must be >= ' (num2str(rx_min_sampling)/1e6) ' MHz.']);
            elseif obj.rx_samplerate > 40e6 || obj.rx2_samplerate > 40e6
                error(['rx_samplerate must be <= ' (num2str(rx_max_sampling)/1e6) ' MHz.']);
            end

            if obj.rx_frequency < rx_min_freq || obj.rx2_frequency < rx_min_freq
                error(['rx_frequency must be >= ' (num2str(rx_min_freq)/1e6) ' MHz.']);
            elseif obj.rx_frequency > rx_max_freq || obj.rx2_frequency > rx_max_freq
                error(['rx_frequency must be <= ' (num2str(rx_max_freq)/1e6) ' MHz.']);
            end
            
            if obj.rx_gain < -10 || obj.rx2_gain < -10
                error('Invalid Gain value. Rx gain must be >= -10');
				elseif obj.rx_gain > 90 || obj.rx2_gain > 90
				error('Invalid Gain value. Rx gain must be <= 90.');
            end
                

            %% Validate TX Properties
            if obj.tx_num_buffers < 1
                error('tx_num_buffers must be > 0.');
            end

            if obj.tx_num_transfers >= obj.tx_num_buffers
                error('tx_num_transfers must be < tx_num_transfers');
            end

            if obj.tx_buf_size < 1024 || mod(obj.tx_buf_size, 1024) ~= 0
                error('tx_buf_size must be a multiple of 1024.');
            end

            if obj.tx_timeout_ms < 0
                error('tx_timeout_ms must be >= 0.');
            end

            if obj.tx_step_size <= 0
                error('tx_step_size must be > 0.');
            end

            if obj.tx_samplerate < 160.0e3 || obj.tx2_samplerate < 160.0e3
                error('tx_samplerate must be >= 160 kHz.');
            elseif obj.tx_samplerate > 40e6 || obj.tx2_samplerate > 40e6
                error('tx_samplerate must be <= 40 MHz.')
            end

            if obj.tx_frequency < tx_min_freq || obj.tx2_frequency < tx_min_freq
                error(['tx_frequency must be >= ' num2str(tx_min_freq) '.']);
            elseif obj.tx_frequency > 3.8e9 || obj.tx2_frequency > 3.8e9
                error('tx_frequency must be <= 3.8 GHz.');
            end
            
            if obj.tx_gain < -10 || obj.tx2_gain < -10
                error('Invalid Gain value. Tx gain must be >= -10');
				elseif obj.tx_gain > 90 || obj.tx2_gain > 90
				error('Invalid Gain value. Tx gain must be <= 90.');
            end
        end
    end
end
