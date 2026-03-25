classdef ChatTransmitterGUI < handle
    % ChatTransmitterGUI MATLAB transmitter-side SDR chat app.

    properties (Access = private)
        Figure              matlab.ui.Figure
        LogArea             matlab.ui.control.TextArea
        PacketArea          matlab.ui.control.TextArea
        InputField          matlab.ui.control.EditField
        SDRDropDown         matlab.ui.control.DropDown
        FrequencyDropDown   matlab.ui.control.DropDown
        PacketizeButton     matlab.ui.control.Button
        SendButton          matlab.ui.control.Button
        PlotButton          matlab.ui.control.Button
        StoredPacket        uint8 = uint8([])
        StoredAFSKWaveform  double = double([])
        StoredFMWaveform    double = double([])
        FMFilePath          char = ''
    end

    methods
        function app = ChatTransmitterGUI()
            app.FMFilePath = fullfile(fileparts(mfilename('fullpath')), 'storedFMSignal.mat');
            app.createComponents();
            app.appendLog('Transmitter ready. Choose SDR, choose frequency, then send a message.');
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure('Name', 'SDR Chat Transmitter', 'Position', [80 80 820 540], 'Color', [0.97 0.98 0.99]);

            uilabel(app.Figure, 'Text', 'SDR Chat Transmitter', 'FontSize', 20, 'FontWeight', 'bold', 'Position', [20 500 280 28]);
            uilabel(app.Figure, 'Text', 'SDR', 'FontWeight', 'bold', 'Position', [20 462 80 22]);
            app.SDRDropDown = uidropdown(app.Figure, 'Items', ChatSignalProcessor.sdrOptions(), 'Value', 'ADALM-PLUTO', 'Position', [20 435 220 26]);

            uilabel(app.Figure, 'Text', 'Frequency Range', 'FontWeight', 'bold', 'Position', [260 462 120 22]);
            app.FrequencyDropDown = uidropdown(app.Figure, 'Items', ChatSignalProcessor.frequencyOptions(), 'Value', '915.00 MHz ISM', 'Position', [260 435 180 26]);

            uilabel(app.Figure, 'Text', 'Message', 'FontWeight', 'bold', 'Position', [20 390 100 22]);
            app.InputField = uieditfield(app.Figure, 'text', 'Position', [20 360 600 30], 'Placeholder', 'Type the chat message to transmit');

            app.PacketizeButton = uibutton(app.Figure, 'push', 'Text', 'Build Packet', 'Position', [640 360 150 30], 'ButtonPushedFcn', @(~,~)app.buildPacketOnly());
            app.SendButton = uibutton(app.Figure, 'push', 'Text', 'Send Message', 'FontWeight', 'bold', 'Position', [640 320 150 30], 'ButtonPushedFcn', @(~,~)app.sendMessage());
            app.PlotButton = uibutton(app.Figure, 'push', 'Text', 'Plot FM Signal', 'Position', [640 280 150 30], 'ButtonPushedFcn', @(~,~)app.plotCurrentFMWaveform());

            uilabel(app.Figure, 'Text', 'AX.25 Packet (Hex)', 'FontWeight', 'bold', 'Position', [20 320 180 22]);
            app.PacketArea = uitextarea(app.Figure, 'Position', [20 200 600 120], 'Editable', 'off', 'Value', {'No packet generated yet.'});

            uilabel(app.Figure, 'Text', 'Transmitter Log', 'FontWeight', 'bold', 'Position', [20 170 120 22]);
            app.LogArea = uitextarea(app.Figure, 'Position', [20 20 770 150], 'Editable', 'off', 'Value', {'Waiting for transmission activity...'});
        end

        function buildPacketOnly(app)
            message = strtrim(app.InputField.Value);
            if strlength(message) == 0
                app.appendLog('Enter a message before building a packet.');
                return;
            end

            app.StoredPacket = ChatSignalProcessor.createAX25Packet(char(message));
            [app.StoredAFSKWaveform, ~, ~] = ChatSignalProcessor.createAFSKWaveform(app.StoredPacket);
            [app.StoredFMWaveform, ~, sampleRate] = ChatSignalProcessor.createFMWaveform(app.StoredAFSKWaveform);
            app.PacketArea.Value = ChatSignalProcessor.wrapPacketHex(app.StoredPacket);

            centerFrequency = ChatSignalProcessor.frequencyFromLabel(app.FrequencyDropDown.Value);
            ChatSignalProcessor.saveFMToFile(app.FMFilePath, app.StoredFMWaveform, sampleRate, centerFrequency, message);

            app.appendLog(sprintf('AX.25 packet built for "%s".', char(message)));
            app.appendLog(sprintf('FM waveform prepared and saved to %s.', app.FMFilePath));
        end

        function sendMessage(app)
            app.buildPacketOnly();
            if isempty(app.StoredFMWaveform)
                return;
            end

            try
                centerFrequency = ChatSignalProcessor.frequencyFromLabel(app.FrequencyDropDown.Value);
                ChatSignalProcessor.transmitViaSelectedSDR(app.SDRDropDown.Value, centerFrequency, app.StoredFMWaveform, app.FMFilePath);
                app.appendLog(sprintf('Transmit request completed via %s at %.2f MHz.', app.SDRDropDown.Value, centerFrequency / 1e6));
            catch exception
                app.appendLog(sprintf('Transmit failed: %s', exception.message));
            end
        end

        function plotCurrentFMWaveform(app)
            if isempty(app.StoredFMWaveform)
                app.appendLog('Build or send a message before plotting the FM waveform.');
                return;
            end

            sampleRate = ChatSignalProcessor.defaultSettings().SampleRate;
            timeAxis = (0:numel(app.StoredFMWaveform) - 1) / sampleRate;
            figure('Name', 'Transmitter FM Waveform', 'NumberTitle', 'off', 'Color', 'w');
            plot(timeAxis, real(app.StoredFMWaveform), 'm');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('FM-Modulated Chat Waveform (Real Part)');
        end

        function appendLog(app, message)
            timestamp = datestr(now, 'HH:MM:SS');
            entry = sprintf('[%s] %s', timestamp, char(message));
            currentValue = app.LogArea.Value;
            if ischar(currentValue)
                currentLines = {currentValue};
            elseif isstring(currentValue) || iscategorical(currentValue)
                currentLines = cellstr(currentValue);
            else
                currentLines = currentValue;
            end

            if isempty(currentLines) || isequal(currentLines, {'Waiting for transmission activity...'})
                app.LogArea.Value = {entry};
            else
                app.LogArea.Value = [currentLines; {entry}];
            end
        end
    end
end
