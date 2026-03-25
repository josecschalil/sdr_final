classdef SimpleChatTransmitterGUI < handle
    % SimpleChatTransmitterGUI Reliable cross-system text sender over TCP.

    properties (Access = private)
        Figure              matlab.ui.Figure
        LogArea             matlab.ui.control.TextArea
        InputField          matlab.ui.control.EditField
        HostField           matlab.ui.control.EditField
        PortField           matlab.ui.control.NumericEditField
        SendButton          matlab.ui.control.Button
    end

    methods
        function app = SimpleChatTransmitterGUI()
            app.createComponents();
            app.appendLog('Transmitter ready. Enter receiver IP and send a message.');
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure( ...
                'Name', 'Simple Chat Transmitter', ...
                'Position', [120 120 760 460], ...
                'Color', [0.98 0.98 0.99]);

            uilabel(app.Figure, ...
                'Text', 'Simple Chat Transmitter', ...
                'FontSize', 20, ...
                'FontWeight', 'bold', ...
                'Position', [20 415 280 28]);

            uilabel(app.Figure, ...
                'Text', 'Receiver IP', ...
                'FontWeight', 'bold', ...
                'Position', [20 375 100 22]);
            app.HostField = uieditfield(app.Figure, 'text', ...
                'Position', [20 345 220 28], ...
                'Value', '127.0.0.1');

            uilabel(app.Figure, ...
                'Text', 'Port', ...
                'FontWeight', 'bold', ...
                'Position', [260 375 80 22]);
            app.PortField = uieditfield(app.Figure, 'numeric', ...
                'Position', [260 345 120 28], ...
                'Limits', [1024 65535], ...
                'RoundFractionalValues', true, ...
                'Value', 55000);

            uilabel(app.Figure, ...
                'Text', 'Message', ...
                'FontWeight', 'bold', ...
                'Position', [20 300 100 22]);
            app.InputField = uieditfield(app.Figure, 'text', ...
                'Position', [20 265 580 30], ...
                'Placeholder', 'Type the message to send');

            app.SendButton = uibutton(app.Figure, 'push', ...
                'Text', 'Send Message', ...
                'FontWeight', 'bold', ...
                'Position', [620 265 120 30], ...
                'ButtonPushedFcn', @(~, ~)app.sendMessage());

            uilabel(app.Figure, ...
                'Text', 'Transmitter Log', ...
                'FontWeight', 'bold', ...
                'Position', [20 225 120 22]);
            app.LogArea = uitextarea(app.Figure, ...
                'Position', [20 20 720 205], ...
                'Editable', 'off', ...
                'Value', {'Waiting to send...'});
        end

        function sendMessage(app)
            host = strtrim(app.HostField.Value);
            port = round(app.PortField.Value);
            message = strtrim(app.InputField.Value);

            if strlength(host) == 0
                app.appendLog('Receiver IP is required.');
                return;
            end

            if strlength(message) == 0
                app.appendLog('Enter a message before sending.');
                return;
            end

            try
                client = tcpclient(host, port, 'Timeout', 5);
                payload = uint8([unicode2native(char(message), 'UTF-8'), 10]);
                write(client, payload, 'uint8');
                clear client
                app.appendLog(sprintf('Sent to %s:%d -> %s', host, port, char(message)));
                app.InputField.Value = '';
            catch exception
                app.appendLog(sprintf('Send failed: %s', exception.message));
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

            if isempty(currentLines) || isequal(currentLines, {'Waiting to send...'})
                app.LogArea.Value = {entry};
            else
                app.LogArea.Value = [currentLines; {entry}];
            end
        end
    end
end
