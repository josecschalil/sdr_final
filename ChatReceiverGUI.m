classdef ChatReceiverGUI < handle
    % ChatReceiverGUI MATLAB receiver-side SDR chat app.

    properties (Access = private)
        Figure              matlab.ui.Figure
        MessagesArea        matlab.ui.control.TextArea
        PacketArea          matlab.ui.control.TextArea
        LogArea             matlab.ui.control.TextArea
        SDRDropDown         matlab.ui.control.DropDown
        FrequencyDropDown   matlab.ui.control.DropDown
        ListenButton        matlab.ui.control.Button
        StopButton          matlab.ui.control.Button
        ReceiveButton       matlab.ui.control.Button
        PlotButton          matlab.ui.control.Button
        StatusLabel         matlab.ui.control.Label
        FMFilePath          char = ''
        LastFMWaveform      double = double([])
        LastPacket          uint8 = uint8([])
        ListenTimer
        PlutoReceiver
        IsListening logical = false
        LastFileTimestamp    char = ''
        LastPacketSignature  char = ''
        ConsecutiveDecodeMisses double = 0
        SignalBuffer         double = double([])
    end

    methods
        function app = ChatReceiverGUI()
            app.FMFilePath = fullfile(fileparts(mfilename('fullpath')), 'storedFMSignal.mat');
            app.createComponents();
            app.appendLog('Receiver ready. Select SDR and frequency, then click Start Listening.');
        end

        function delete(app)
            app.stopListening();
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure( ...
                'Name', 'SDR Chat Receiver', ...
                'Position', [940 80 820 540], ...
                'Color', [0.96 0.98 0.97], ...
                'CloseRequestFcn', @(src, event)app.onFigureClosed()); %#ok<INUSD>

            uilabel(app.Figure, 'Text', 'SDR Chat Receiver', 'FontSize', 20, 'FontWeight', 'bold', 'Position', [20 500 260 28]);
            uilabel(app.Figure, 'Text', 'SDR', 'FontWeight', 'bold', 'Position', [20 462 80 22]);
            app.SDRDropDown = uidropdown(app.Figure, 'Items', ChatSignalProcessor.sdrOptions(), 'Value', 'ADALM-PLUTO', 'Position', [20 435 220 26]);

            uilabel(app.Figure, 'Text', 'Frequency Range', 'FontWeight', 'bold', 'Position', [260 462 120 22]);
            app.FrequencyDropDown = uidropdown(app.Figure, 'Items', ChatSignalProcessor.frequencyOptions(), 'Value', '915.00 MHz ISM', 'Position', [260 435 180 26]);

            app.ListenButton = uibutton(app.Figure, 'push', 'Text', 'Start Listening', 'FontWeight', 'bold', 'Position', [470 435 110 30], 'ButtonPushedFcn', @(~,~)app.startListening());
            app.StopButton = uibutton(app.Figure, 'push', 'Text', 'Stop', 'Position', [590 435 70 30], 'ButtonPushedFcn', @(~,~)app.stopListening());
            app.ReceiveButton = uibutton(app.Figure, 'push', 'Text', 'Receive Once', 'Position', [670 435 120 30], 'ButtonPushedFcn', @(~,~)app.receiveMessage());
            app.PlotButton = uibutton(app.Figure, 'push', 'Text', 'Plot Received FM', 'Position', [640 395 150 30], 'ButtonPushedFcn', @(~,~)app.plotReceivedWaveform());
            app.StatusLabel = uilabel(app.Figure, 'Text', 'Status: Idle', 'FontWeight', 'bold', 'Position', [470 395 150 22]);

            uilabel(app.Figure, 'Text', 'Received Text', 'FontWeight', 'bold', 'Position', [20 390 120 22]);
            app.MessagesArea = uitextarea(app.Figure, 'Position', [20 250 770 140], 'Editable', 'off', 'Value', {'No received messages yet.'});

            uilabel(app.Figure, 'Text', 'Recovered AX.25 Packet (Hex)', 'FontWeight', 'bold', 'Position', [20 220 220 22]);
            app.PacketArea = uitextarea(app.Figure, 'Position', [20 100 770 120], 'Editable', 'off', 'Value', {'No recovered packet yet.'});

            uilabel(app.Figure, 'Text', 'Receiver Log', 'FontWeight', 'bold', 'Position', [20 70 120 22]);
            app.LogArea = uitextarea(app.Figure, 'Position', [20 20 770 50], 'Editable', 'off', 'Value', {'Waiting for receive activity...'});
        end

        function receiveMessage(app)
            try
                messageReceived = app.processIncomingSignal();
                if ~messageReceived
                    app.appendLog('No new decodable packet was detected on this check.');
                end
            catch exception
                app.appendLog(sprintf('Receive failed: %s', exception.message));
            end
        end

        function startListening(app)
            if app.IsListening
                app.appendLog('Receiver is already listening.');
                return;
            end

            try
                app.SignalBuffer = double([]);
                app.prepareListenerResources();
                app.ListenTimer = timer( ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'Period', 1.0, ...
                    'BusyMode', 'drop', ...
                    'TimerFcn', @(~, ~)app.listenTick());
                start(app.ListenTimer);
                app.IsListening = true;
                app.StatusLabel.Text = 'Status: Listening';
                app.appendLog(sprintf('Listening started on %s at %s.', app.SDRDropDown.Value, app.FrequencyDropDown.Value));
            catch exception
                app.stopListening();
                app.appendLog(sprintf('Unable to start listening: %s', exception.message));
            end
        end

        function stopListening(app)
            if ~isempty(app.ListenTimer) && isvalid(app.ListenTimer)
                stop(app.ListenTimer);
                delete(app.ListenTimer);
            end
            app.ListenTimer = [];

            if ~isempty(app.PlutoReceiver)
                release(app.PlutoReceiver);
            end
            app.PlutoReceiver = [];
            app.SignalBuffer = double([]);

            app.IsListening = false;
            if ~isempty(app.StatusLabel) && isvalid(app.StatusLabel)
                app.StatusLabel.Text = 'Status: Idle';
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
            plot(timeAxis, real(app.LastFMWaveform), 'k');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('Received FM Chat Waveform (Real Part)');
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

        function listenTick(app)
            try
                messageReceived = app.processIncomingSignal();
                if messageReceived
                    app.ConsecutiveDecodeMisses = 0;
                    app.StatusLabel.Text = sprintf('Status: Last packet %s', datestr(now, 'HH:MM:SS'));
                end
            catch exception
                if app.isRecoverableDecodeError(exception)
                    app.ConsecutiveDecodeMisses = app.ConsecutiveDecodeMisses + 1;
                    if mod(app.ConsecutiveDecodeMisses, 10) == 1
                        app.appendLog('Listening: signal detected but no valid AX.25 packet decoded yet.');
                    end
                else
                    app.appendLog(sprintf('Listening error: %s', exception.message));
                    app.stopListening();
                end
            end
        end

        function prepareListenerResources(app)
            centerFrequency = ChatSignalProcessor.frequencyFromLabel(app.FrequencyDropDown.Value);
            settings = ChatSignalProcessor.defaultSettings();

            app.stopListening();
            selection = char(app.SDRDropDown.Value);
            if strcmp(selection, 'ADALM-PLUTO')
                app.PlutoReceiver = sdrrx('Pluto', ...
                    'CenterFrequency', centerFrequency, ...
                    'BasebandSampleRate', settings.PlutoBasebandSampleRate, ...
                    'SamplesPerFrame', settings.PlutoFrameLength, ...
                    'GainSource', 'Manual', ...
                    'Gain', settings.PlutoRxGain, ...
                    'OutputDataType', 'double');
            else
                app.PlutoReceiver = [];
            end
        end

        function messageReceived = processIncomingSignal(app)
            centerFrequency = ChatSignalProcessor.frequencyFromLabel(app.FrequencyDropDown.Value);
            selection = char(app.SDRDropDown.Value);
            [fmWaveform, sampleRate, sourceChanged] = app.fetchCurrentSignal(selection, centerFrequency);

            if ~sourceChanged || isempty(fmWaveform)
                messageReceived = false;
                return;
            end

            if max(abs(fmWaveform)) < 0.01
                messageReceived = false;
                return;
            end

            recoveredPacket = ChatSignalProcessor.recoverPacketFromFMWaveform(fmWaveform, sampleRate);
            recoveredText = ChatSignalProcessor.decodeAX25Packet(recoveredPacket);
            packetSignature = sprintf('%02X', recoveredPacket);

            if strcmp(packetSignature, app.LastPacketSignature)
                messageReceived = false;
                return;
            end

            app.LastFMWaveform = fmWaveform;
            app.LastPacket = recoveredPacket;
            app.LastPacketSignature = packetSignature;
            app.PacketArea.Value = ChatSignalProcessor.wrapPacketHex(recoveredPacket);
            app.appendMessage(recoveredText);
            app.appendLog(sprintf('Message received via %s at %.2f MHz.', app.SDRDropDown.Value, centerFrequency / 1e6));
            messageReceived = true;
        end

        function [fmWaveform, sampleRate, sourceChanged] = fetchCurrentSignal(app, selection, centerFrequency)
            settings = ChatSignalProcessor.defaultSettings();

            switch selection
                case 'ADALM-PLUTO'
                    if isempty(app.PlutoReceiver)
                        app.prepareListenerResources();
                    end
                    receivedSamples = app.PlutoReceiver();
                    app.SignalBuffer = [app.SignalBuffer, receivedSamples(:).'];
                    maxBufferSamples = 4 * settings.PlutoFrameLength;
                    if numel(app.SignalBuffer) > maxBufferSamples
                        app.SignalBuffer = app.SignalBuffer(end - maxBufferSamples + 1:end);
                    end
                    fmWaveform = app.SignalBuffer;
                    sampleRate = settings.SampleRate;
                    sourceChanged = true;
                case {'Simulation File Loopback', 'No SDR (Signal Demo)'}
                    if ~isfile(app.FMFilePath)
                        fmWaveform = [];
                        sampleRate = settings.SampleRate;
                        sourceChanged = false;
                        return;
                    end

                    fileInfo = dir(app.FMFilePath);
                    fileTimestamp = fileInfo.date;
                    if strcmp(fileTimestamp, app.LastFileTimestamp)
                        fmWaveform = [];
                        sampleRate = settings.SampleRate;
                        sourceChanged = false;
                        return;
                    end

                    loaded = ChatSignalProcessor.loadFMFromFile(app.FMFilePath);
                    metadata = loaded.metadata;
                    if isfield(metadata, 'CenterFrequency') && abs(metadata.CenterFrequency - centerFrequency) > 1
                        fmWaveform = [];
                        sampleRate = settings.SampleRate;
                        sourceChanged = false;
                        return;
                    end

                    app.LastFileTimestamp = fileTimestamp;
                    fmWaveform = loaded.savedWaveform;
                    app.SignalBuffer = fmWaveform;
                    sampleRate = metadata.SampleRate;
                    sourceChanged = true;
                otherwise
                    error('Unsupported SDR selection.');
            end
        end

        function onFigureClosed(app)
            app.stopListening();
            delete(app.Figure);
        end

        function isRecoverable = isRecoverableDecodeError(~, exception)
            recoverableMessages = { ...
                'CRC check failed', ...
                'Unable to find AX.25 flag bytes', ...
                'Unable to recover a CRC-valid AX.25 packet', ...
                'No valid AX.25 packet was recovered across tested symbol offsets', ...
                'Recovered payload does not contain any full bytes', ...
                'Packet is too short to be a valid AX.25 UI frame'};

            isRecoverable = false;
            for index = 1:numel(recoverableMessages)
                if contains(exception.message, recoverableMessages{index})
                    isRecoverable = true;
                    return;
                end
            end
        end
    end
end
