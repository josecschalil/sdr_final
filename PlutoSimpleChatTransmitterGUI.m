classdef PlutoSimpleChatTransmitterGUI < handle
    % PlutoSimpleChatTransmitterGUI Simple Pluto-based transmitter for text messages.

    properties (Access = private)
        Figure              matlab.ui.Figure
        LogArea             matlab.ui.control.TextArea
        InputField          matlab.ui.control.EditField
        SDRDropDown         matlab.ui.control.DropDown
        FrequencyDropDown   matlab.ui.control.DropDown
        SendButton          matlab.ui.control.Button
        PlotButton          matlab.ui.control.Button
        StoredWaveform
        FilePath            char = ''
    end

    methods
        function app = PlutoSimpleChatTransmitterGUI()
            app.FilePath = fullfile(fileparts(mfilename('fullpath')), 'simplePlutoChatWaveform.mat');
            app.createComponents();
            app.appendLog('Pluto transmitter ready. Type a message and send.');
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure('Name', 'Pluto Simple Chat Transmitter', 'Position', [100 100 800 480], 'Color', [0.98 0.98 0.99]);

            uilabel(app.Figure, 'Text', 'Pluto Simple Chat Transmitter', 'FontSize', 20, 'FontWeight', 'bold', 'Position', [20 430 320 28]);
            uilabel(app.Figure, 'Text', 'SDR', 'FontWeight', 'bold', 'Position', [20 390 80 22]);
            app.SDRDropDown = uidropdown(app.Figure, 'Items', PlutoSimpleChatCodec.sdrOptions(), 'Value', 'ADALM-PLUTO', 'Position', [20 360 220 26]);

            uilabel(app.Figure, 'Text', 'Frequency Range', 'FontWeight', 'bold', 'Position', [270 390 120 22]);
            app.FrequencyDropDown = uidropdown(app.Figure, 'Items', PlutoSimpleChatCodec.frequencyOptions(), 'Value', '433.92 MHz ISM', 'Position', [270 360 180 26]);

            uilabel(app.Figure, 'Text', 'Message', 'FontWeight', 'bold', 'Position', [20 315 80 22]);
            app.InputField = uieditfield(app.Figure, 'text', 'Position', [20 280 610 30], 'Placeholder', 'Type the message to transmit');
            app.SendButton = uibutton(app.Figure, 'push', 'Text', 'Send Message', 'FontWeight', 'bold', 'Position', [650 280 120 30], 'ButtonPushedFcn', @(~, ~)app.sendMessage());
            app.PlotButton = uibutton(app.Figure, 'push', 'Text', 'Plot Waveform', 'Position', [650 240 120 30], 'ButtonPushedFcn', @(~, ~)app.plotWaveform());

            uilabel(app.Figure, 'Text', 'Transmitter Log', 'FontWeight', 'bold', 'Position', [20 240 120 22]);
            app.LogArea = uitextarea(app.Figure, 'Position', [20 20 750 220], 'Editable', 'off', 'Value', {'Waiting for transmitter activity...'});
        end

        function sendMessage(app)
            message = strtrim(app.InputField.Value);
            if strlength(message) == 0
                app.appendLog('Enter a message before sending.');
                return;
            end

            try
                centerFrequency = PlutoSimpleChatCodec.frequencyFromLabel(app.FrequencyDropDown.Value);
                app.StoredWaveform = PlutoSimpleChatCodec.createTransmitWaveform(char(message));
                PlutoSimpleChatCodec.transmit(app.SDRDropDown.Value, centerFrequency, app.StoredWaveform, app.FilePath);
                app.appendLog(sprintf('Message sent via %s at %.2f MHz: %s', app.SDRDropDown.Value, centerFrequency / 1e6, char(message)));
                app.InputField.Value = '';
            catch exception
                app.appendLog(sprintf('Transmit failed: %s', exception.message));
            end
        end

        function plotWaveform(app)
            if isempty(app.StoredWaveform)
                app.appendLog('Send a message first to generate a waveform.');
                return;
            end

            sampleRate = PlutoSimpleChatCodec.defaultSettings().SampleRate;
            timeAxis = (0:numel(app.StoredWaveform) - 1) / sampleRate;
            figure('Name', 'Pluto Transmit Waveform', 'NumberTitle', 'off', 'Color', 'w');
            plot(timeAxis, real(app.StoredWaveform), 'b');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('Transmit Waveform (Real Part)');
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

            if isempty(currentLines) || isequal(currentLines, {'Waiting for transmitter activity...'})
                app.LogArea.Value = {entry};
            else
                app.LogArea.Value = [currentLines; {entry}];
            end
        end
    end
end
