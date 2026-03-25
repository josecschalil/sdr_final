classdef ChatReceiverGUI < handle
    % ChatReceiverGUI MATLAB receiver-side SDR chat app.

    properties (Access = private)
        Figure              matlab.ui.Figure
        MessagesArea        matlab.ui.control.TextArea
        PacketArea          matlab.ui.control.TextArea
        LogArea             matlab.ui.control.TextArea
        SDRDropDown         matlab.ui.control.DropDown
        FrequencyDropDown   matlab.ui.control.DropDown
        ReceiveButton       matlab.ui.control.Button
        PlotButton          matlab.ui.control.Button
        FMFilePath          char = ''
        LastFMWaveform      double = double([])
        LastPacket          uint8 = uint8([])
    end

    methods
        function app = ChatReceiverGUI()
            app.FMFilePath = fullfile(fileparts(mfilename('fullpath')), 'storedFMSignal.mat');
            app.createComponents();
            app.appendLog('Receiver ready. Select SDR and frequency, then click Receive.');
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure('Name', 'SDR Chat Receiver', 'Position', [940 80 820 540], 'Color', [0.96 0.98 0.97]);

            uilabel(app.Figure, 'Text', 'SDR Chat Receiver', 'FontSize', 20, 'FontWeight', 'bold', 'Position', [20 500 260 28]);
            uilabel(app.Figure, 'Text', 'SDR', 'FontWeight', 'bold', 'Position', [20 462 80 22]);
            app.SDRDropDown = uidropdown(app.Figure, 'Items', ChatSignalProcessor.sdrOptions(), 'Value', 'ADALM-PLUTO', 'Position', [20 435 220 26]);

            uilabel(app.Figure, 'Text', 'Frequency Range', 'FontWeight', 'bold', 'Position', [260 462 120 22]);
            app.FrequencyDropDown = uidropdown(app.Figure, 'Items', ChatSignalProcessor.frequencyOptions(), 'Value', '915.00 MHz ISM', 'Position', [260 435 180 26]);

            app.ReceiveButton = uibutton(app.Figure, 'push', 'Text', 'Receive Message', 'FontWeight', 'bold', 'Position', [470 435 150 30], 'ButtonPushedFcn', @(~,~)app.receiveMessage());
            app.PlotButton = uibutton(app.Figure, 'push', 'Text', 'Plot Received FM', 'Position', [640 435 150 30], 'ButtonPushedFcn', @(~,~)app.plotReceivedWaveform());

            uilabel(app.Figure, 'Text', 'Received Text', 'FontWeight', 'bold', 'Position', [20 390 120 22]);
            app.MessagesArea = uitextarea(app.Figure, 'Position', [20 250 770 140], 'Editable', 'off', 'Value', {'No received messages yet.'});

            uilabel(app.Figure, 'Text', 'Recovered AX.25 Packet (Hex)', 'FontWeight', 'bold', 'Position', [20 220 220 22]);
            app.PacketArea = uitextarea(app.Figure, 'Position', [20 100 770 120], 'Editable', 'off', 'Value', {'No recovered packet yet.'});

            uilabel(app.Figure, 'Text', 'Receiver Log', 'FontWeight', 'bold', 'Position', [20 70 120 22]);
            app.LogArea = uitextarea(app.Figure, 'Position', [20 20 770 50], 'Editable', 'off', 'Value', {'Waiting for receive activity...'});
        end

        function receiveMessage(app)
            try
                centerFrequency = ChatSignalProcessor.frequencyFromLabel(app.FrequencyDropDown.Value);
                [fmWaveform, sampleRate] = ChatSignalProcessor.receiveViaSelectedSDR(app.SDRDropDown.Value, centerFrequency, app.FMFilePath);
                recoveredAFSK = ChatSignalProcessor.demodulateFMSignal(fmWaveform, sampleRate);
                recoveredBits = ChatSignalProcessor.demodulateAFSKBits(recoveredAFSK, sampleRate);
                recoveredPacket = ChatSignalProcessor.extractPacketFromBits(recoveredBits);
                recoveredText = ChatSignalProcessor.decodeAX25Packet(recoveredPacket);

                app.LastFMWaveform = fmWaveform;
                app.LastPacket = recoveredPacket;
                app.PacketArea.Value = ChatSignalProcessor.wrapPacketHex(recoveredPacket);
                app.appendMessage(recoveredText);
                app.appendLog(sprintf('Message received via %s at %.2f MHz.', app.SDRDropDown.Value, centerFrequency / 1e6));
            catch exception
                app.appendLog(sprintf('Receive failed: %s', exception.message));
            end
        end

        function plotReceivedWaveform(app)
            if isempty(app.LastFMWaveform)
                app.appendLog('Receive a message before plotting the waveform.');
                return;
            end

            sampleRate = ChatSignalProcessor.defaultSettings().SampleRate;
            timeAxis = (0:numel(app.LastFMWaveform) - 1) / sampleRate;
            figure('Name', 'Receiver FM Waveform', 'NumberTitle', 'off', 'Color', 'w');
            plot(timeAxis, app.LastFMWaveform, 'k');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('Received FM Chat Waveform');
        end

        function appendMessage(app, message)
            currentValue = app.MessagesArea.Value;
            entry = sprintf('Peer: %s', char(message));

            if ischar(currentValue)
                currentLines = {currentValue};
            elseif isstring(currentValue) || iscategorical(currentValue)
                currentLines = cellstr(currentValue);
            else
                currentLines = currentValue;
            end

            if isempty(currentLines) || isequal(currentLines, {'No received messages yet.'})
                app.MessagesArea.Value = {entry};
            else
                app.MessagesArea.Value = [currentLines; {entry}];
            end
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

            if isempty(currentLines) || isequal(currentLines, {'Waiting for receive activity...'})
                app.LogArea.Value = {entry};
            else
                app.LogArea.Value = [currentLines; {entry}];
            end
        end
    end
end
