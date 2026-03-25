classdef SimpleChatReceiverGUI < handle
    % SimpleChatReceiverGUI Reliable cross-system text receiver over TCP.

    properties (Access = private)
        Figure              matlab.ui.Figure
        MessagesArea        matlab.ui.control.TextArea
        LogArea             matlab.ui.control.TextArea
        PortField           matlab.ui.control.NumericEditField
        StartButton         matlab.ui.control.Button
        StopButton          matlab.ui.control.Button
        StatusLabel         matlab.ui.control.Label
        Server
    end

    methods
        function app = SimpleChatReceiverGUI()
            app.createComponents();
            app.appendLog('Receiver ready. Click Start Listening.');
        end

        function delete(app)
            app.stopListening();
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure( ...
                'Name', 'Simple Chat Receiver', ...
                'Position', [920 120 760 460], ...
                'Color', [0.97 0.99 0.97], ...
                'CloseRequestFcn', @(~, ~)app.onClose());

            uilabel(app.Figure, ...
                'Text', 'Simple Chat Receiver', ...
                'FontSize', 20, ...
                'FontWeight', 'bold', ...
                'Position', [20 415 240 28]);

            uilabel(app.Figure, ...
                'Text', 'Listen Port', ...
                'FontWeight', 'bold', ...
                'Position', [20 375 100 22]);
            app.PortField = uieditfield(app.Figure, 'numeric', ...
                'Position', [20 345 140 28], ...
                'Limits', [1024 65535], ...
                'RoundFractionalValues', true, ...
                'Value', 55000);

            app.StartButton = uibutton(app.Figure, 'push', ...
                'Text', 'Start Listening', ...
                'FontWeight', 'bold', ...
                'Position', [190 345 120 30], ...
                'ButtonPushedFcn', @(~, ~)app.startListening());

            app.StopButton = uibutton(app.Figure, 'push', ...
                'Text', 'Stop', ...
                'Position', [325 345 80 30], ...
                'ButtonPushedFcn', @(~, ~)app.stopListening());

            app.StatusLabel = uilabel(app.Figure, ...
                'Text', 'Status: Idle', ...
                'FontWeight', 'bold', ...
                'Position', [430 349 160 22]);

            uilabel(app.Figure, ...
                'Text', 'Received Messages', ...
                'FontWeight', 'bold', ...
                'Position', [20 300 140 22]);
            app.MessagesArea = uitextarea(app.Figure, ...
                'Position', [20 145 720 155], ...
                'Editable', 'off', ...
                'Value', {'No messages received yet.'});

            uilabel(app.Figure, ...
                'Text', 'Receiver Log', ...
                'FontWeight', 'bold', ...
                'Position', [20 110 120 22]);
            app.LogArea = uitextarea(app.Figure, ...
                'Position', [20 20 720 90], ...
                'Editable', 'off', ...
                'Value', {'Waiting for receiver activity...'});
        end

        function startListening(app)
            if ~isempty(app.Server)
                app.appendLog('Receiver is already listening.');
                return;
            end

            port = round(app.PortField.Value);
            try
                app.Server = tcpserver( ...
                    "0.0.0.0", port, ...
                    'ConnectionChangedFcn', @(src, event)app.onConnectionChanged(src, event), ...
                    'BytesAvailableFcnMode', 'terminator', ...
                    'Terminator', "LF", ...
                    'BytesAvailableFcn', @(src, event)app.onMessageReceived(src, event));
                app.StatusLabel.Text = sprintf('Status: Listening on %d', port);
                app.appendLog(sprintf('Listening on port %d.', port));
            catch exception
                app.appendLog(sprintf('Unable to start receiver: %s', exception.message));
            end
        end

        function stopListening(app)
            if isempty(app.Server)
                app.StatusLabel.Text = 'Status: Idle';
                return;
            end

            clearServer = app.Server;
            app.Server = [];
            try
                configureCallback(clearServer, "off");
            catch
            end
            delete(clearServer);
            app.StatusLabel.Text = 'Status: Idle';
            app.appendLog('Receiver stopped.');
        end

        function onConnectionChanged(app, ~, event)
            try
                if event.Connected
                    app.appendLog('Sender connected.');
                else
                    app.appendLog('Sender disconnected.');
                end
            catch
                app.appendLog('Connection state changed.');
            end
        end

        function onMessageReceived(app, src, ~)
            try
                bytes = readline(src);
                message = strtrim(char(bytes));
                if strlength(message) == 0
                    return;
                end

                app.appendMessage(message);
                app.appendLog(sprintf('Received message: %s', message));
            catch exception
                app.appendLog(sprintf('Receive failed: %s', exception.message));
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

        function onClose(app)
            app.stopListening();
            delete(app.Figure);
        end
    end
end
