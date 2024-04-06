% bladeRF RX/TX control and configuration.
%
% This is a submodule of the bladeRF object. It is not intended to be
% accessed directly, but through the top-level bladeRF object.
%

%
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

%% Control and configuration of transceiver properties
classdef bladeRF_MIMO_XCVR < handle

    properties
        config          % Stream configuration. See bladeRF_StreamConfig.
        corrections     % IQ corrections. See bladeRF_MIMO_IQCorr.
    end

    properties(Dependent = true)
        agc             % Enable automatic gain control ['AUTO', 'MANUAL', 'FAST', 'SLOW']
        gain            % Universal gain setting. This value is standardized to output 0dBm when set to 60.
        biastee         % Control biastee
        samplerate      % Samplerate. Must be within 160 kHz and 40 MHz. A 2-3 MHz minimum is suggested unless external filters are being used.
        frequency       % Frequency. Must be within [237.5 MHz, 3.8 GHz] when no XB-200 is attached, or [0 GHz, 3.8 GHz] when an XB-200 is attached.
        bandwidth       % LPF bandwidth seting. This is rounded to the nearest of the available discrete settings. It is recommended to set this and read back the actual value.
        vga1            % VGA1 gain. RX range: [5, 30], TX Range: [-35, -4]
        vga2            % VGA2 gain. RX range: [0, 30], TX range: [0, 25]
        lna             % RX LNA gain. Values: { 'BYPASS', 'MID', 'MAX' }
        xb200_filter    % XB200 Filter selection. Only valid when an XB200 is attached. Options are: '50M', '144M', '222M', 'AUTO_1DB', 'AUTO_3DB', 'CUSTOM'
        mux             % FPGA sample FIFO mux mode. Only valid for RX, with options 'BASEBAND_LMS', '12BIT_COUNTER', '32BIT_COUNTER', 'DIGITAL_LOOPBACK'
        channel         % Channel number
    end

    properties(SetAccess = immutable, Hidden=true)
        bladerf         % Associated bladeRF device handle
        module          % Module specifier (as a libbladeRF enum)
        direction       % Module direction: { 'RX', 'TX' }
        min_frequency   % Lower frequency tuning limit
        max_frequency   % Higher frequency tuning limit
        min_sampling    % Lower sampling rate tuning limit
        max_sampling    % Higher sampling rate  tuning limit
        xb200_attached; % Modify behavior due to XB200 being attached
    end

    properties(SetAccess = private, Hidden=true)
        current_channel % Current active channel
    end

    properties(SetAccess = private)
        running         % Denotes whether or not the module is enabled to stream samples.
        timestamp       % Provides a coarse readback of the timestamp counter.
    end

    properties(Access={?bladeRF_MIMO})
        sob = true      % TX Start of Burst (Applicable to TX only.)
        eob = false     % TX end-of-burst flag (Applicable to TX only.)
		
    end
	
	properties(SetAccess = private)
		enable_rx_mimo = false
		enable_tx_mimo = false
    end
	

    methods
        %% Property handling

        % Samplerate
        function set.samplerate(obj, val) %% Bitti
            % Create the holding structures
            rate = libstruct('bladerf_rational_rate');
            actual = libstruct('bladerf_rational_rate');

            % Set the samplerate
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
			
			input = val;
				for i = 1:2
					% Requested rate
				    rate.integer = floor(input(i));
					[rate.num, rate.den] = rat(mod(input(i),1));
					
					[status, ~, ~, actual] = calllib('libbladeRF', 'bladerf_set_rational_sample_rate', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), rate, rate);
					bladeRF_MIMO.check_status('bladerf_set_rational_sample_rate', status);
					fprintf("The samplerate is set:%d for %s\n",val(i),char(obj.current_channel(i)));
				end
			else
					rate.integer = floor(val);
					[rate.num, rate.den] = rat(mod(val,1));
				
					[status, ~, ~, actual] = calllib('libbladeRF', 'bladerf_set_rational_sample_rate', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), rate, rate);
					bladeRF_MIMO.check_status('bladerf_set_rational_sample_rate', status);
					warning("The samplerate is set:%d for %s",val,obj.current_channel);
			end
            %fprintf('Set %s samplerate. Requested: %d + %d/%d, Actual: %d + %d/%d\n', ...
            %        obj.direction, ...
            %        rate.integer, rate.num, rate.den, ...
            %        actual.integer, actual.num, actual.den);
        end

        function samplerate_val = get.samplerate(obj) %% Bitti
            rate = libstruct('bladerf_rational_rate');
            rate.integer = 0;
            rate.num = 0;
            rate.den = 1;

            % Get the sample rate from the hardware
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
					rate2 = libstruct('bladerf_rational_rate');
					rate2.integer = 0;
					rate2.num = 0;
					rate2.den = 1;
				
					[status, ~, rate] = calllib('libbladeRF', 'bladerf_get_rational_sample_rate', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel{1}), rate);
					bladeRF_MIMO.check_status('bladerf_get_rational_sample_rate', status);
					
					[status, ~, rate2] = calllib('libbladeRF', 'bladerf_get_rational_sample_rate', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel{2}), rate2);
					bladeRF_MIMO.check_status('bladerf_get_rational_sample_rate', status);			
					
					samplerate_val = [ (rate.integer + rate.num / rate.den) , (rate2.integer + rate2.num / rate2.den) ];
				
			else
				[status, ~, rate] = calllib('libbladeRF', 'bladerf_get_rational_sample_rate', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), rate);
				bladeRF_MIMO.check_status('bladerf_get_rational_sample_rate', status);
				samplerate_val = rate.integer + rate.num / rate.den;
			end
            %fprintf('Read %s samplerate: %d + %d/%d\n', ...
            %        obj.direction, rate.integer, rate.num, rate.den);
      
        end

        % Frequency
        function set.frequency(obj, val) %% Bitti
			input = val;
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				for i = 1:2
					[status, ~] = calllib('libbladeRF', 'bladerf_set_frequency', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), input(i));
					bladeRF_MIMO.check_status('bladerf_set_frequency', status);
					fprintf("The frequency is set:%d for %s\n",val(i),char(obj.current_channel(i)));
				end
			else
				[status, ~] = calllib('libbladeRF', 'bladerf_set_frequency', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), input);
				bladeRF_MIMO.check_status('bladerf_set_frequency', status);	
				warning("The frequency is set:%d for %s",val,obj.current_channel);				
			end
        end

        function freq_val = get.frequency(obj)%% Bitti
			output = [uint32(0),uint32(0)];
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				for i=1:2
				[status, ~, output(i)] = calllib('libbladeRF', 'bladerf_get_frequency', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), output(i));
				bladeRF_MIMO.check_status('bladerf_get_frequency', status);
				end
				freq_val = output;
			else
				[status, ~, output(1)] = calllib('libbladeRF', 'bladerf_get_frequency', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), output(1));
				bladeRF_MIMO.check_status('bladerf_get_frequency', status);		
				freq_val = output(1);
			end
            %fprintf('Read %s frequency: %f\n', obj.direction, freq_val);
        end

        % Configures the LPF bandwidth on the associated module
        function set.bandwidth(obj, val) %% Bitti
            actual = [uint32(0),uint32(0)];
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				actual = [uint32(0),uint32(0)];
				for i=1:2
					[status, ~, actual(i)] = calllib('libbladeRF', 'bladerf_set_bandwidth', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), val(i), actual(i));
					bladeRF_MIMO.check_status('bladerf_set_bandwidth', status);	
					fprintf("The bandwidth is set:%d for %s\n",val(i),char(obj.current_channel(i)));					
				end
			else
				actual = uint32(0);
			    [status, ~, actual] = calllib('libbladeRF', 'bladerf_set_bandwidth', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), val, actual);
				bladeRF_MIMO.check_status('bladerf_set_bandwidth', status);
				warning("The bandwidth is set:%d for %s",val,obj.current_channel);
			end
            %fprintf('Set %s bandwidth. Requested: %f, Actual: %f\n', ...
            %        obj.direction, val, actual)
        end

        % Reads the LPF bandwidth configuration on the associated module
        function bw_val = get.bandwidth(obj) %%Bitti
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				bw_val = [uint32(0),uint32(0)];
				for i=1:2
					[status, ~, bw_val(i)] = calllib('libbladeRF', 'bladerf_get_bandwidth', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), bw_val(i));
					bladeRF_MIMO.check_status('bladerf_get_bandwidth', status);
				end
			else
				bw_val = uint32(0);
				[status, ~, bw_val] = calllib('libbladeRF', 'bladerf_get_bandwidth', obj.bladerf.device, obj.module, bw_val);
				bladeRF_MIMO.check_status('bladerf_get_bandwidth', status);
			end
            %fprintf('Read %s bandwidth: %f\n', obj.direction, bw_val);
        end

        % Configures the automatic gain control setting
        function set.agc(obj, val) %%Bitti
		
			if(obj.enable_rx_mimo == true)

				for i=1:2
					
					switch lower(char(val(i)))
						case 'auto'
							agc_val{i} = 'BLADERF_GAIN_DEFAULT';
						case 'manual'
							agc_val{i} = 'BLADERF_GAIN_MGC';
						case 'fast'
							agc_val{i} = 'BLADERF_GAIN_FASTATTACK_AGC';
						case 'enable'
							agc_val{i} = 'BLADERF_GAIN_SLOWATTACK_AGC';
						case 'slow'
							agc_val{i} = 'BLADERF_GAIN_SLOWATTACK_AGC';
						case 'hybrid'
							agc_val{i} = 'BLADERF_GAIN_HYBRID_AGC';
						otherwise
							error(strcat('Invalid AGC setting: ', val{i}));
					end	
					[status, ~] = calllib('libbladeRF', 'bladerf_set_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), agc_val{i});
					if status == -8
						if obj.bladerf.info.gen == 1
							disp('Cannot enable AGC. AGC DC LUT file is missing, run `cal table agc rx'' in bladeRF-cli.')
						end
					else
						bladeRF_MIMO.check_status('bladerf_set_gain_mode', status);
					end
					fprintf("The agc is set:%s for %s\n",char(val(i)),char(obj.current_channel(i)));
				end
			else
			    switch lower(val)
					case 'auto'
						agc_val = 'BLADERF_GAIN_DEFAULT';
					case 'manual'
						agc_val = 'BLADERF_GAIN_MGC';
					case 'fast'
						agc_val = 'BLADERF_GAIN_FASTATTACK_AGC';
					case 'enable'
						agc_val = 'BLADERF_GAIN_SLOWATTACK_AGC';
					case 'slow'
						agc_val = 'BLADERF_GAIN_SLOWATTACK_AGC';
					case 'hybrid'
						agc_val = 'BLADERF_GAIN_HYBRID_AGC';
					otherwise
						error(strcat('Invalid AGC setting: ', val));
				end
				[status, ~] = calllib('libbladeRF', 'bladerf_set_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), agc_val);
				if status == -8
					if obj.bladerf.info.gen == 1
						disp('Cannot enable AGC. AGC DC LUT file is missing, run `cal table agc rx'' in bladeRF-cli.')
					end
				else
					bladeRF_MIMO.check_status('bladerf_set_gain_mode', status);
				end
				warning("The agc is set:%s for %s",val,obj.current_channel);
			end
			

        end

        % Reads the current automatic gain control setting
        function val = get.agc(obj) %%Bitti
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				%val = [int32(0),int32(0)];
				tmp = [int32(0),int32(0)];
				for i=1:2
					[status, ~, mode{i}] = calllib('libbladeRF', 'bladerf_get_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), tmp(i));
					bladeRF_MIMO.check_status('bladerf_get_gain_mode', status);

					switch char(mode{i})
						case 'BLADERF_GAIN_DEFAULT'
							val{i} = 'auto';
						case 'BLADERF_GAIN_MGC'
							val{i} = 'manual';
						case 'BLADERF_GAIN_FASTATTACK_AGC'
							val{i} = 'fast';
						case 'BLADERF_GAIN_SLOWATTACK_AGC'
							val{i} = 'slow';
						case 'BLADERF_GAIN_HYBRID_AGC'
							val{i} = 'hybrid';
						otherwise
							error(strcat('Invalid AGC setting: ', val{i}));
					end		
				end
			else
				val = int32(0);
				tmp = int32(0);
				[status, ~, mode] = calllib('libbladeRF', 'bladerf_get_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), tmp);
				bladeRF_MIMO.check_status('bladerf_get_gain_mode', status);

				switch mode
					case 'BLADERF_GAIN_DEFAULT'
						val = 'auto';
					case 'BLADERF_GAIN_MGC'
						val = 'manual';
					case 'BLADERF_GAIN_FASTATTACK_AGC'
						val = 'fast';
					case 'BLADERF_GAIN_SLOWATTACK_AGC'
						val = 'slow';
					case 'BLADERF_GAIN_HYBRID_AGC'
						val = 'hybrid';
					otherwise
						error(strcat('Invalid AGC setting: ', val));
				end
            %fprintf('Read %s gain: %d\n', obj.direction, val);
			end		
            
        end
		
        % Configures active channel setting
        function set.channel(obj, val) %% Burası bitti
            if (strcmpi(val,'RX') == true || strcmpi(val, 'RX1') || strcmp(val, 'BLADERF_CHANNEL_RX1'))
                channel = 'BLADERF_CHANNEL_RX1';
            elseif (strcmpi(val, 'RX2') || strcmp(val, 'BLADERF_CHANNEL_RX2'))
                channel = 'BLADERF_CHANNEL_RX2';
            elseif (strcmpi(val,'TX') == true || strcmpi(val, 'TX1') || strcmp(val, 'BLADERF_CHANNEL_TX1'))
                channel = 'BLADERF_CHANNEL_TX1';
            elseif (strcmpi(val, 'TX2') || strcmp(val, 'BLADERF_CHANNEL_TX2'))
                channel = 'BLADERF_CHANNEL_TX2';
			elseif obj.enable_tx_mimo == true
				channel = {'BLADERF_CHANNEL_TX1', 'BLADERF_CHANNEL_TX2'};
			elseif obj.enable_rx_mimo == true
				channel = {'BLADERF_CHANNEL_RX1', 'BLADERF_CHANNEL_RX2'};
			else
				error('channel is not set');
            end
			
            obj.current_channel = channel;

            if obj.running % It is never called !!! , enable module in the start function
				if obj.enable_tx_mimo == true || obj.enable_rx_mimo == true
					for i = 1:2
						[status, ~] = calllib('libbladeRF', 'bladerf_enable_module', ...
											obj.bladerf.device, ...
											bladeRF_MIMO.str2ch(char(obj.current_channel(i))), ...
											false);

						bladeRF_MIMO.check_status('bladerf_enable_module', status);
					end
				else
						[status, ~] = calllib('libbladeRF', 'bladerf_enable_module', ...
											obj.bladerf.device, ...
											bladeRF_MIMO.str2ch(obj.current_channel), ...
											false);

						bladeRF_MIMO.check_status('bladerf_enable_module', status);	
						warning("The module is enabled for %s",obj.current_channel);				
				end

            end

        end

        % Reads the current active channel setting
        function val = get.channel(obj) %% Burası bitti
            val = obj.current_channel
        end

        % Configures the universal gain
        function set.gain(obj, val) %% Burası bitti
			
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				for i=1:2
					if strcmpi(obj.direction,'RX') == true && strcmpi(obj.agc(i),'manual') == false
						warning(['Cannot set ' obj.direction ' gain when AGC is in ' char(obj.agc(i)) ' mode'])
					end
					[status, ~] = calllib('libbladeRF', 'bladerf_set_gain', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), val(i));
					bladeRF_MIMO.check_status('bladerf_set_gain', status);
					fprintf("The gain is set:%d for %s\n",val(i),char(obj.current_channel(i)));
				end
			else
				if strcmpi(obj.direction,'RX') == true && strcmpi(obj.agc,'manual') == false
					warning(['Cannot set ' obj.direction ' gain when AGC is in ' obj.agc ' mode'])
				end
				[status, ~] = calllib('libbladeRF', 'bladerf_set_gain', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), val);
				bladeRF_MIMO.check_status('bladerf_set_gain', status);
				warning("The gain is set:%d for %s",val,obj.current_channel);
			end			
			
			
			

        end

        % Reads the current universal gain configuration
        function val = get.gain(obj) %% Burası bitti
		
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)

				for i=1:2
					val = [int32(0),int32(0)];
					tmp = [int32(0),int32(0)];
					[status, ~, val(i)] = calllib('libbladeRF', 'bladerf_get_gain', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), tmp(i));
					bladeRF_MIMO.check_status('bladerf_get_gain', status);		
				end
			else
				val = int32(0);
				tmp = int32(0);
				[status, ~, val] = calllib('libbladeRF', 'bladerf_get_gain', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), tmp);
				bladeRF_MIMO.check_status('bladerf_get_gain', status);
			end		


            %fprintf('Read %s gain: %d\n', obj.direction, val);
        end

        % Configures the gain of VGA1
        function set.vga1(obj, val) %% Burası bitti
		
			if strcmpi(obj.direction,'RX') == true
                [status, ~] = calllib('libbladeRF', 'bladerf_set_rxvga1', obj.bladerf.device, val);
				warning("The vga1 is set for RX");
			elseif strcmpi(obj.direction,'TX') == true
				[status, ~] = calllib('libbladeRF', 'bladerf_set_txvga1', obj.bladerf.device, val);
				warning("The vga1 is set for TX");
            end
		
            bladeRF_MIMO.check_status('bladerf_set_vga1', status);

            %fprintf('Set %s VGA1: %d\n', obj.direction, val);
        end

        % Reads the current VGA1 gain configuration
        function val = get.vga1(obj) %% Burası bitti
            if obj.bladerf.info.gen ~= 1
                val = 0;
                return
            end

            val = int32(0);
			if strcmpi(obj.direction,'RX') == true
                [status, ~] = calllib('libbladeRF', 'bladerf_get_rxvga1', obj.bladerf.device, val);
			elseif strcmpi(obj.direction,'TX') == true
				[status, ~] = calllib('libbladeRF', 'bladerf_get_txvga1', obj.bladerf.device, val);
            end

            bladeRF_MIMO.check_status('bladerf_get_vga1', status);

            %fprintf('Read %s VGA1: %d\n', obj.direction, val);
        end

        % Configures the gain of VGA2
        function set.vga2(obj, val) %% Burası bitti
		
			if strcmpi(obj.direction,'RX') == true
                [status, ~] = calllib('libbladeRF', 'bladerf_set_rxvga2', obj.bladerf.device, val);
				warning("The vga2 is set for RX");
			elseif strcmpi(obj.direction,'TX') == true
				[status, ~] = calllib('libbladeRF', 'bladerf_set_txvga2', obj.bladerf.device, val);
				warning("The vga2 is set for TX");
            end

            bladeRF_MIMO.check_status('bladerf_set_vga2', status);

            %fprintf('Set %s VGA2: %d\n', obj.direction, obj.vga2);
        end

        % Reads the current VGA2 configuration
        function val = get.vga2(obj) %% Burası bitti
            if obj.bladerf.info.gen ~= 1
                val = 0;
                return
            end

            val = int32(0);
			
			if strcmpi(obj.direction,'RX') == true
                [status, ~] = calllib('libbladeRF', 'bladerf_get_rxvga2', obj.bladerf.device, val);
			elseif strcmpi(obj.direction,'TX') == true
				[status, ~] = calllib('libbladeRF', 'bladerf_get_txvga2', obj.bladerf.device, val);
			end

            bladeRF_MIMO.check_status('bladerf_get_vga2', status);

            %fprintf('Read %s VGA2: %d\n', obj.direction, val);
        end

        % Configure the RX LNA gain
        function set.lna(obj, val) %% Burası bitti
            if strcmpi(obj.direction,'TX') == true
                error('LNA gain is not applicable to the TX path');
            end

            valid_value = true;

            if isnumeric(val)
                switch val
                    case 0
                        lna_val = 'BLADERF_LNA_GAIN_BYPASS';

                    case 3
                        lna_val = 'BLADERF_LNA_GAIN_MID';

                    case 6
                        lna_val = 'BLADERF_LNA_GAIN_MAX';

                    otherwise
                        valid_value = false;
                end
            else
				val = lower(val);
                if strcmpi(val,'bypass')   == true
                    lna_val = 'BLADERF_LNA_GAIN_BYPASS';
                elseif strcmpi(val, 'mid') == true
                    lna_val = 'BLADERF_LNA_GAIN_MID';
                elseif strcmpi(val, 'max') == true
                    lna_val = 'BLADERF_LNA_GAIN_MAX';
                else
                    valid_value = false;
                end
            end

            if valid_value ~= true
                error('Valid LNA values are [''BYPASS'', ''MID'', ''MAX''] or [0, 3, 6], respectively.');
            else
                [status, ~] = calllib('libbladeRF', 'bladerf_set_lna_gain', obj.bladerf.device, lna_val);
                bladeRF_MIMO.check_status('bladerf_set_lna_gain', status);
				warning("The LNA is set for RX");
                %fprintf('Set RX LNA gain to: %s\n', lna_val);
            end
        end

        % Read current RX LNA gain setting
        function val = get.lna(obj) %% Burası bitti
            if obj.bladerf.info.gen ~= 1
                val = 0;
                return
            end
            if strcmpi(obj.direction,'TX') == true
                error('LNA gain is not applicable to the TX path');
            end

            val = 0;
            [status, ~, lna] = calllib('libbladeRF', 'bladerf_get_lna_gain', obj.bladerf.device, val);
            bladeRF_MIMO.check_status('bladerf_get_lna_gain', status);

            if strcmpi(lna, 'BLADERF_LNA_GAIN_BYPASS') == true
                val = 'BYPASS';
            elseif strcmpi(lna, 'BLADERF_LNA_GAIN_MID') == true
                val = 'MID';
            elseif strcmpi(lna, 'BLADERF_LNA_GAIN_MAX') == true
                val = 'MAX';
            else
                val = 'UNKNOWN';
            end

            %fprintf('Got RX LNA gain: %s\n', val);
        end
			
        % Configures the bias tee
        function set.biastee(obj, val)  %% Burası bitti
		
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				for i=1:2
					[status, ~] = calllib('libbladeRF', 'bladerf_set_bias_tee', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), val(i));
					fprintf("The biastee is set:%d for %s\n",val(i),char(obj.current_channel(i)));
				end
			else
				[status, ~] = calllib('libbladeRF', 'bladerf_set_bias_tee', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), val);
				warning('The biastee is set:%d for %s',val,obj.current_channel)
			end



            %fprintf('Set %s biastee: %d\n', obj.direction, obj.vga2);
        end

        % Reads the current bias tee configuration
        function val = get.biastee(obj) %% Burası bitti
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				for i=1:2
					tmp = [int32(0),int32(0)];
					[status, ~, val(i)] = calllib('libbladeRF', 'bladerf_get_bias_tee', obj.bladerf.device,bladeRF_MIMO.str2ch(char(obj.current_channel(i))), tmp(i));
				end
			else
				tmp = int32(0);
				[status, ~, val] = calllib('libbladeRF', 'bladerf_get_bias_tee', obj.bladerf.device,bladeRF_MIMO.str2ch(obj.current_channel), tmp);
			end


            %fprintf('Get %s biastee: %d\n', obj.direction, val);
        end

        % Read the timestamp counter from the associated module
        function val = get.timestamp(obj) %% Burası bitti , directiona göre değer döndürüyor tx or rx
            val = uint64(0);			
            [status, ~, val] = calllib('libbladeRF', 'bladerf_get_timestamp', obj.bladerf.device, strcat('BLADERF_', obj.direction), val);
            bladeRF_MIMO.check_status('bladerf_get_timestamp', status);
        end

        % Set the current XB200 filter
        function set.xb200_filter(obj, filter) %% Burası bitti
            if obj.xb200_attached == false
                error('Cannot set XB200 filter because the handle was not initialized for use with the XB200.');
            end
			
			filter = upper(filter);
			switch filter
				case '50M'
				case '144M'
				case '222M'
				case 'AUTO_1DB'
				case 'AUTO_3DB'
				case 'CUSTOM'
				otherwise
				error(['Invalid XB200 filter: ' filter]);
			end
			filter_val = ['BLADERF_XB200_' filter ];
			
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)

				for i=1:2					
					status = calllib('libbladeRF', 'bladerf_xb200_set_filterbank', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), filter_val);
					bladeRF_MIMO.check_status('bladerf_xb200_set_filterbank', status);		
				end
			else
				status = calllib('libbladeRF', 'bladerf_xb200_set_filterbank', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), filter_val);
				bladeRF_MIMO.check_status('bladerf_xb200_set_filterbank', status);
				warning("The XB200 filter is set:%s for %s",filter_val,obj.current_channel);
			end
			
            
        end

        % Get the current XB200 filter
        function filter_val = get.xb200_filter(obj) %% Burası bitti
            if obj.xb200_attached == false
                filter_val = 'N/A';
                return;
            end
			
			
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				filter_val = [0,0];
				for i=1:2
					[status, ~, filter_val(i)] = calllib('libbladeRF', 'bladerf_xb200_get_filterbank', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), filter_val(i));
					bladeRF_MIMO.check_status('bladerf_xb200_get_filterbank', status);						
				end
				filter_val = [strrep(filter_val, 'BLADERF_XB200_', ''),strrep(filter_val, 'BLADERF_XB200_', '')];
			else
				filter_val = 0;
				[status, ~, filter_val] = calllib('libbladeRF', 'bladerf_xb200_get_filterbank', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), filter_val);
				bladeRF_MIMO.check_status('bladerf_xb200_get_filterbank', status);	
				filter_val = strrep(filter_val, 'BLADERF_XB200_', '');
			end    
        end

        % Set the RX mux mode setting
        function set.mux(obj, mode) %% Burası bitti
            if strcmpi(obj.direction, 'TX') == true
                error('FPGA sample mux mode configuration is only applicable to the RX module.');
            end

            mode = upper(mode);
            switch mode
                case { 'BASEBAND_LMS', '12BIT_COUNTER', '32BIT_COUNTER', 'DIGITAL_LOOPBACK' }
                    mode = ['BLADERF_RX_MUX_' mode ];
                otherwise
                    error(['Invalid RX mux mode: ' mode]);
            end

            status = calllib('libbladeRF', 'bladerf_set_rx_mux', obj.bladerf.device, mode);
            bladeRF_MIMO.check_status('bladerf_set_rx_mux', status);
			warning("The RX mux mode is set:%s for %s",mode,obj.current_channel);
        end

        % Get the current RX mux mode setting
        function mode = get.mux(obj) %% Burası bitti
            if strcmpi(obj.direction, 'TX') == true
                error('FPGA sample mux mode configuration is only applicable to the RX module.');
            end

            mode = 'BLADERF_RX_MUX_INVALID';

            [status, ~, mode] = calllib('libbladeRF', 'bladerf_get_rx_mux', obj.bladerf.device, mode);
            bladeRF_MIMO.check_status('bladerf_get_rx_mux', status);

            mode = strrep(mode, 'BLADERF_RX_MUX_', '');
        end

        % Constructor
        function obj = bladeRF_MIMO_XCVR(dev, dir, xb) %% Burası bitti
            if strcmpi(dir,'RX') == false && strcmpi(dir,'TX') == false && strcmpi(dir,'TX2') == false && strcmpi(dir,'RX2') == false && strcmpi(dir,'RX_MIMO') == false && strcmpi(dir,'TX_MIMO') == false
                error('Invalid direction specified');
            end

            % Set the direction of the transceiver
			if strcmpi(dir,'RX') == true || strcmpi(dir,'RX2') == true || strcmpi(dir,'RX_MIMO') == true
				obj.direction = 'RX';
			elseif strcmpi(dir,'TX') == true || strcmpi(dir,'TX2') == true ||strcmpi(dir,'TX_MIMO') == true
				obj.direction = 'TX';
			end
			
            if strcmpi(dir,'RX_MIMO') == true % Check if RX_MIMO is requested
				obj.enable_rx_mimo = true;
			else
				obj.enable_rx_mimo = false;
			end
			
			if strcmpi(dir,'TX_MIMO') == true % Check if TX_MIMO is requested
				obj.enable_tx_mimo = true;
			else
				obj.enable_tx_mimo = false;
			end
			
			obj.bladerf = dev;
            obj.channel = dir; % set.channel function will handle this
			
			if strcmpi(dir,'RX') == true || strcmpi(dir,'RX2') == true
				obj.module = 0; %  BLADERF_RX_X1
			elseif strcmpi(dir,'TX') == true || strcmpi(dir,'TX2') == true
				obj.module = 1; %  BLADERF_TX_X1
			elseif strcmpi(dir,'RX_MIMO') == true
				obj.module = 2; %  BLADERF_RX_X2
			elseif strcmpi(dir,'TX_MIMO') == true
				obj.module = 3;	%  BLADERF_TX_X2
			end

            if strcmpi(xb, 'XB200') == true
                obj.min_frequency = 0;
                obj.xb200_attached = true;
                obj.xb200_filter = 'AUTO_3DB';
            else
                obj.min_frequency = 237.5e6;
                obj.xb200_attached = false;
            end

            % Setup defaults
			obj.config = bladeRF_StreamConfig;
			
			if obj.enable_rx_mimo == true || obj.enable_tx_mimo
				obj.samplerate = [3e6,3e6];
				obj.frequency = [1.0e9,1.0e9];
				obj.bandwidth = [1.5e6,1.5e6];
			else
				obj.samplerate = 3e6;
				obj.frequency = 1.0e9;
				obj.bandwidth = 1.5e6;
			end
			
            freqrange = libstruct('bladerf_range');
			samplerange = libstruct('bladerf_range');
			if obj.enable_rx_mimo == true || obj.enable_tx_mimo
				status = calllib('libbladeRF', 'bladerf_get_frequency_range', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(1))), freqrange);
				bladeRF_MIMO.check_status('bladerf_get_frequency_range', status);
				status = calllib('libbladeRF', 'bladerf_get_sample_rate_range', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(1))), samplerange);
				bladeRF_MIMO.check_status('bladerf_get_frequency_range', status);				
			else
				status = calllib('libbladeRF', 'bladerf_get_frequency_range', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), freqrange);
				bladeRF_MIMO.check_status('bladerf_get_frequency_range', status);
				status = calllib('libbladeRF', 'bladerf_get_sample_rate_range', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), samplerange);
				bladeRF_MIMO.check_status('bladerf_get_frequency_range', status);				
			end

            obj.min_frequency = freqrange.min;
            obj.max_frequency = freqrange.max;
            obj.min_sampling = samplerange.min;
            obj.max_sampling = samplerange.max;
			
			if obj.enable_rx_mimo == true
				for i = 1:2
					status = calllib('libbladeRF', 'bladerf_set_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), 'BLADERF_GAIN_DEFAULT');
					if status == -8
						if obj.bladerf.info.gen == 1
							disp('Cannot enable AGC. AGC DC LUT file is missing, run `cal table agc rx'' in bladeRF-cli.')
						end
					else
						bladeRF_MIMO.check_status('bladerf_set_gain_mode', status);
					end

					gainmode = int32(0);
					[status, ~, gainmode] = calllib('libbladeRF', 'bladerf_get_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(char(obj.current_channel(i))), gainmode);
					bladeRF_MIMO.check_status('bladerf_get_gain_mode', status);
				end				
			else
				if strcmpi(dir,'RX') == true
					status = calllib('libbladeRF', 'bladerf_set_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), 'BLADERF_GAIN_DEFAULT');
					if status == -8
						if obj.bladerf.info.gen == 1
							disp('Cannot enable AGC. AGC DC LUT file is missing, run `cal table agc rx'' in bladeRF-cli.')
						end
					else
						bladeRF_MIMO.check_status('bladerf_set_gain_mode', status);
					end

					gainmode = int32(0);
					[status, ~, gainmode] = calllib('libbladeRF', 'bladerf_get_gain_mode', obj.bladerf.device, bladeRF_MIMO.str2ch(obj.current_channel), gainmode);
					bladeRF_MIMO.check_status('bladerf_get_gain_mode', status);
				end
			
			end


            if dev.info.gen == 1
                if strcmpi(dir,'RX') == true
                    obj.vga1 = 30;
                    obj.vga2 = 0;
                    obj.lna = 'MAX';
                else
                    obj.vga1 = -8;
                    obj.vga2 = 16;
                end
            end
            obj.corrections = bladeRF_MIMO_IQCorr(dev, obj.module, 0, 0, 0, 0,obj.current_channel); 
            obj.running = false;
        end


        function start(obj) %% Burası bitti gibi
        % Apply stream configuration parameters and enable the module.
        %
        % bladeRF_MIMO.rx.start() or bladeRF_MIMO.tx.start().
        %
            %fprintf('Starting %s stream.\n', obj.direction);

            obj.running = true;
            obj.config.lock();

            % If we're starting up a TX module, reset our cached EOB/SOB
            % flags so that we can internally take care of these if the
            % user doesn't want to worry about them.
            if strcmpi(obj.direction,'TX') == true
                obj.sob = true;
                obj.eob = false;
            end

            % Configure the sync config
            [status, ~] = calllib('libbladeRF', 'bladerf_sync_config', ...
                                  obj.bladerf.device, ...
                                  obj.module, ...
                                  'BLADERF_FORMAT_SC16_Q11_META', ...
                                  obj.config.num_buffers, ...
                                  obj.config.buffer_size, ...
                                  obj.config.num_transfers, ...
                                  obj.config.timeout_ms);


            bladeRF_MIMO.check_status('bladerf_sync_config', status);

            % Enable the module
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)
				for i=1:2
					[status, ~] = calllib('libbladeRF', 'bladerf_enable_module', ...
										  obj.bladerf.device, ...
										  bladeRF_MIMO.str2ch(char(obj.current_channel(i))), ...
										  true);

					bladeRF_MIMO.check_status('bladerf_enable_module', status);				
				end
			else
				[status, ~] = calllib('libbladeRF', 'bladerf_enable_module', ...
									  obj.bladerf.device, ...
									  bladeRF_MIMO.str2ch(obj.current_channel), ...
									  true);

				bladeRF_MIMO.check_status('bladerf_enable_module', status);
				warning("The module is enabled for %s",obj.current_channel);
			end
			
        end

        function stop(obj) %% Burası bitti gibi
        % Stop streaming and disable the module
        %
        % bladeRF_MIMO.rx.stop() or bladeRF_MIMO.tx.stop().
        %
            %fprintf('Stopping %s module.\n', obj.direction);

            % If the user is trying top stop "mid-burst", we'll want to
            % end the burst to ensure the TX DAC is reset to 0+0j
            if strcmpi(obj.direction,'TX') == true
                if obj.sob == false && obj.eob == false
                    obj.eob = true;
					if( obj.enable_tx_mimo == true )
						obj.bladerf.transmit([0,0], 0, obj.sob, obj.eob);
					else
						obj.bladerf.transmit(0, 0, obj.sob, obj.eob);
					end
                    % Ensure these zeros are transmitted by waiting for
                    % any remaining data in buffers to flush
                    max_buffered =  obj.bladerf.tx.config.num_buffers * ...
                                    obj.bladerf.tx.config.buffer_size;

                    target_time = obj.bladerf.tx.timestamp + ...
                                  max_buffered;

                    while obj.bladerf.tx.timestamp <= target_time
                        pause(1e-3);
                    end
                end
            end

            % Disable the module
			if(obj.enable_rx_mimo == true || obj.enable_tx_mimo == true)

				for i=1:2			
					[status, ~] = calllib('libbladeRF', 'bladerf_enable_module', ...
										  obj.bladerf.device, ...
										  bladeRF_MIMO.str2ch(char(obj.current_channel(i))), ...
										  false);
					bladeRF_MIMO.check_status('bladerf_enable_module', status);		
				end
			else
				[status, ~] = calllib('libbladeRF', 'bladerf_enable_module', ...
									  obj.bladerf.device, ...
									  bladeRF_MIMO.str2ch(obj.current_channel), ...
									  false);

				bladeRF_MIMO.check_status('bladerf_enable_module', status);
			end			

            % Unlock the configuration for changing
            obj.config.unlock();
            obj.running = false;
        end
    end
end
