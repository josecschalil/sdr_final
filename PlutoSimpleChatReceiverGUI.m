classdef PlutoSimpleChatReceiverGUI < handle
    % PlutoSimpleChatReceiverGUI Simple Pluto-based receiver with automatic listening.

    properties (Access = private)
        Figure              matlab.ui.Figure
        MessagesArea        matlab.ui.control.TextArea
        LogArea             matlab.ui.control.TextArea
        SDRDropDown         matlab.ui.control.DropDown
        FrequencyDropDown   matlab.ui.control.DropDown
        StartButton         matlab.ui.control.Button
        StopButton          matlab.ui.control.Button
        ReceiveButton       matlab.ui.control.Button
        StatusLabel         matlab.ui.control.Label
        PowerLabel          matlab.ui.control.Label
        TimerObj
        Receiver
        FilePath            char = ''
        LastMessage         char = ''
        LastFileTimestamp   char = ''
        SignalBuffer
        LatestFrame
        TickCount double = 0
    end

    methods
        function app = PlutoSimpleChatReceiverGUI()
            app.FilePath = fullfile(fileparts(mfilename('fullpath')), 'simplePlutoChatWaveform.mat');
            app.createComponents();
            app.appendLog('Pluto receiver ready. Click Start Listening.');
        end

        function delete(app)
            app.stopListening();
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure( ...
                'Name', 'Pluto Simple Chat Receiver', ...
                'Position', [940 100 820 500], ...
                'Color', [0.97 0.99 0.97], ...
                'CloseRequestFcn', @(~, ~)app.onClose());

            uilabel(app.Figure, 'Text', 'Pluto Simple Chat Receiver', 'FontSize', 20, 'FontWeight', 'bold', 'Position', [20 450 300 28]);
            uilabel(app.Figure, 'Text', 'SDR', 'FontWeight', 'bold', 'Position', [20 410 80 22]);
            app.SDRDropDown = uidropdown(app.Figure, 'Items', PlutoSimpleChatCodec.sdrOptions(), 'Value', 'ADALM-PLUTO', 'Position', [20 380 220 26]);

            uilabel(app.Figure, 'Text', 'Frequency Range', 'FontWeight', 'bold', 'Position', [270 410 120 22]);
            app.FrequencyDropDown = uidropdown(app.Figure, 'Items', PlutoSimpleChatCodec.frequencyOptions(), 'Value', '915.00 MHz ISM', 'Position', [270 380 180 26]);

            app.StartButton = uibutton(app.Figure, 'push', 'Text', 'Start Listening', 'FontWeight', 'bold', 'Position', [480 380 120 30], 'ButtonPushedFcn', @(~, ~)app.startListening());
            app.StopButton = uibutton(app.Figure, 'push', 'Text', 'Stop', 'Position', [615 380 80 30], 'ButtonPushedFcn', @(~, ~)app.stopListening());
            app.ReceiveButton = uibutton(app.Figure, 'push', 'Text', 'Receive Once', 'Position', [710 380 90 30], 'ButtonPushedFcn', @(~, ~)app.receiveOnce());
            app.StatusLabel = uilabel(app.Figure, 'Text', 'Status: Idle', 'FontWeight', 'bold', 'Position', [480 345 180 22]);
            app.PowerLabel = uilabel(app.Figure, 'Text', 'Signal: -- dB', 'Position', [670 345 130 22]);

            uilabel(app.Figure, 'Text', 'Received Messages', 'FontWeight', 'bold', 'Position', [20 335 140 22]);
            app.MessagesArea = uitextarea(app.Figure, 'Position', [20 170 780 165], 'Editable', 'off', 'Value', {'No messages received yet.'});

            uilabel(app.Figure, 'Text', 'Receiver Log', 'FontWeight', 'bold', 'Position', [20 135 120 22]);
            app.LogArea = uitextarea(app.Figure, 'Position', [20 20 780 115], 'Editable', 'off', 'Value', {'Waiting for receiver activity...'});
        end

        function startListening(app)
            if ~isempty(app.TimerObj) && isvalid(app.TimerObj)
                app.appendLog('Receiver is already listening.');
                return;
            end

            try
                app.prepareReceiver();
                app.TimerObj = timer( ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'Period', 0.2, ...
                    'BusyMode', 'drop', ...
                    'TimerFcn', @(~, ~)app.listenTick());
                start(app.TimerObj);
                app.StatusLabel.Text = 'Status: Listening';
                app.appendLog(sprintf('Listening on %s via %s.', app.FrequencyDropDown.Value, app.SDRDropDown.Value));
            catch exception
                app.stopListening();
                app.appendLog(sprintf('Unable to start listening: %s', exception.message));
            end
        end

        function stopListening(app)
            if ~isempty(app.TimerObj) && isvalid(app.TimerObj)
                stop(app.TimerObj);
                delete(app.TimerObj);
            end
            app.TimerObj = [];

            if ~isempty(app.Receiver)
                release(app.Receiver);
            end
            app.Receiver = [];
            app.SignalBuffer = [];
            app.LatestFrame = [];
            app.TickCount = 0;
            app.StatusLabel.Text = 'Status: Idle';
        end

        function receiveOnce(app)
            try
                didReceive = app.processIncoming();
                if ~didReceive
                    app.appendLog('No decodable message was found in this capture.');
                end
            catch exception
                app.appendLog(sprintf('Receive failed: %s', exception.message));
            end
        end

        function listenTick(app)
            try
                app.TickCount = app.TickCount + 1;
                didReceive = app.processIncoming();
                if didReceive
                    app.StatusLabel.Text = sprintf('Status: Last message %s', datestr(now, 'HH:MM:SS'));
                end
            catch exception
                app.appendLog(sprintf('Listening issue: %s', exception.message));
            end
        end

        function prepareReceiver(app)
            app.stopListening();
            app.LastFileTimestamp = '';
            app.SignalBuffer = [];
            app.LatestFrame = [];
            app.TickCount = 0;
            selection = char(app.SDRDropDown.Value);
            if strcmp(selection, 'ADALM-PLUTO')
                centerFrequency = PlutoSimpleChatCodec.frequencyFromLabel(app.FrequencyDropDown.Value);
                app.Receiver = PlutoSimpleChatCodec.createReceiver(centerFrequency);
            else
                app.Receiver = [];
            end
        end

        function didReceive = processIncoming(app)
            [samples, sourceChanged] = app.fetchSamples();
            if ~sourceChanged || isempty(samples)
                didReceive = false;
                return;
            end

            powerDb = app.measurePowerDb(app.LatestFrame);
            app.PowerLabel.Text = sprintf('Signal: %.1f dB', powerDb);
            if mod(app.TickCount, 10) == 0
                app.appendLog(sprintf('Listening power level: %.1f dB', powerDb));
            end
            if powerDb < -45
                didReceive = false;
                return;
            end

            [message, ~] = PlutoSimpleChatCodec.recoverMessage(samples);
            if strcmp(char(message), app.LastMessage)
                didReceive = false;
                return;
            end

            app.LastMessage = char(message);
            app.appendMessage(message);
            app.appendLog(sprintf('Received message: %s', char(message)));
            didReceive = true;
        end

        function [samples, sourceChanged] = fetchSamples(app)
            selection = char(app.SDRDropDown.Value);

            switch selection
                case 'ADALM-PLUTO'
                    if isempty(app.Receiver)
                        app.prepareReceiver();
                    end
                    app.LatestFrame = app.Receiver();
                    app.SignalBuffer = [app.SignalBuffer; app.LatestFrame(:)];
                    maxBufferSamples = 4 * PlutoSimpleChatCodec.defaultSettings().PlutoFrameLength;
                    if numel(app.SignalBuffer) > maxBufferSamples
                        app.SignalBuffer = app.SignalBuffer(end - maxBufferSamples + 1:end);
                    end
                    samples = app.SignalBuffer;
                    sourceChanged = true;
                case 'Simulation File Loopback'
                    if ~isfile(app.FilePath)
                        samples = [];
                        sourceChanged = false;
                        return;
                    end

                    fileInfo = dir(app.FilePath);
                    if strcmp(fileInfo.date, app.LastFileTimestamp)
                        samples = [];
                        sourceChanged = false;
                        return;
                    end

                    loaded = PlutoSimpleChatCodec.loadWaveform(app.FilePath);
                    centerFrequency = PlutoSimpleChatCodec.frequencyFromLabel(app.FrequencyDropDown.Value);
                    if isfield(loaded.metadata, 'CenterFrequency') && abs(loaded.metadata.CenterFrequency - centerFrequency) > 1
                        samples = [];
                        sourceChanged = false;
                        return;
                    end

                    app.LastFileTimestamp = fileInfo.date;
                    samples = loaded.savedWaveform;
                    app.LatestFrame = samples;
                    app.SignalBuffer = samples(:);
                    sourceChanged = true;
                otherwise
                    error('Unsupported SDR selection.');
            end
        end

        function appendMessage(app, message)
            entry = sprintf('Peer: %s', char(message));
            currentValue = app.MessagesArea.Value;

            if ischar(currentValue)
                currentLines = {currentValue};
            elseif isstring(currentValue) || iscategorical(currentValue)
                currentLines = cellstr(currentValue);
            else
                currentLines = currentValue;
            end

            if isempty(currentLines) || isequal(currentLines, {'No messages received yet.'})
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

            if isempty(currentLines) || isequal(currentLines, {'Waiting for receiver activity...'})
                app.LogArea.Value = {entry};
            else
                app.LogArea.Value = [currentLines; {entry}];
            end
        end

        function powerDb = measurePowerDb(~, samples)
            magnitude = abs(samples);
            powerDb = 20 * log10(sqrt(mean(magnitude .^ 2)) + eps);
        end

        function onClose(app)
            app.stopListening();
            delete(app.Figure);
        end
    end
end
