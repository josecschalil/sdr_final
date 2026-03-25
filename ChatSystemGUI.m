classdef ChatSystemGUI < handle
    % ChatSystemGUI Simple GUI shell for a digital chat system.

    properties (Access = private)
        Figure              matlab.ui.Figure
        LogArea             matlab.ui.control.TextArea
        PacketArea          matlab.ui.control.TextArea
        InputField          matlab.ui.control.EditField
        SendButton          matlab.ui.control.Button
        DecodeButton        matlab.ui.control.Button
        ModulateButton      matlab.ui.control.Button
        FMModulateButton    matlab.ui.control.Button
        RecoverButton       matlab.ui.control.Button
        HeaderLabel         matlab.ui.control.Label
        StoredPacket        uint8 = uint8([])
        StoredWaveform      double = double([])
        StoredFMWaveform    double = double([])
        StoredFMFilePath    char = ''
    end

    methods
        function app = ChatSystemGUI()
            createComponents(app);
            appendSystemMessage(app, 'Digital chat system initialized.');
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Figure = uifigure( ...
                'Name', 'Digital Chat System', ...
                'Position', [100 100 760 500], ...
                'Color', [0.96 0.97 0.99]);

            app.HeaderLabel = uilabel(app.Figure, ...
                'Text', 'Digital Chat System', ...
                'FontSize', 20, ...
                'FontWeight', 'bold', ...
                'Position', [20 455 300 28]);

            uilabel(app.Figure, ...
                'Text', 'Chat Log', ...
                'FontSize', 13, ...
                'FontWeight', 'bold', ...
                'Position', [20 420 120 22]);

            app.LogArea = uitextarea(app.Figure, ...
                'Position', [20 205 720 210], ...
                'Editable', 'off', ...
                'Value', {'Waiting for messages...'});

            uilabel(app.Figure, ...
                'Text', 'Stored AX.25 Packet (Hex)', ...
                'FontSize', 13, ...
                'FontWeight', 'bold', ...
                'Position', [20 165 220 22]);

            app.PacketArea = uitextarea(app.Figure, ...
                'Position', [20 95 720 70], ...
                'Editable', 'off', ...
                'Value', {'No packet stored.'});

            uilabel(app.Figure, ...
                'Text', 'Message Input', ...
                'FontSize', 13, ...
                'FontWeight', 'bold', ...
                'Position', [20 57 120 22]);

            app.InputField = uieditfield(app.Figure, 'text', ...
                'Position', [20 20 470 32], ...
                'Placeholder', 'Type a message and press Send', ...
                'ValueChangedFcn', @(src, event)onEnterPressed(app)); %#ok<INUSD>

            app.SendButton = uibutton(app.Figure, 'push', ...
                'Text', 'Packetize', ...
                'FontWeight', 'bold', ...
                'Position', [270 20 110 32], ...
                'ButtonPushedFcn', @(src, event)sendMessage(app)); %#ok<INUSD>

            app.DecodeButton = uibutton(app.Figure, 'push', ...
                'Text', 'Depacketize', ...
                'FontWeight', 'bold', ...
                'Position', [395 20 110 32], ...
                'ButtonPushedFcn', @(src, event)decodeStoredPacket(app)); %#ok<INUSD>

            app.ModulateButton = uibutton(app.Figure, 'push', ...
                'Text', 'AFSK Modulate', ...
                'FontWeight', 'bold', ...
                'Position', [520 20 105 32], ...
                'ButtonPushedFcn', @(src, event)modulateStoredPacket(app)); %#ok<INUSD>

            app.FMModulateButton = uibutton(app.Figure, 'push', ...
                'Text', 'FM Modulate', ...
                'FontWeight', 'bold', ...
                'Position', [640 20 100 32], ...
                'ButtonPushedFcn', @(src, event)fmModulateStoredWaveform(app)); %#ok<INUSD>

            app.RecoverButton = uibutton(app.Figure, 'push', ...
                'Text', 'Recover Text', ...
                'FontWeight', 'bold', ...
                'Position', [640 58 100 32], ...
                'ButtonPushedFcn', @(src, event)recoverTextFromFMSignal(app)); %#ok<INUSD>
        end

        function onEnterPressed(app)
            sendMessage(app);
        end

        function sendMessage(app)
            message = strtrim(app.InputField.Value);

            if strlength(message) == 0
                return;
            end

            packet = app.createAX25Packet(char(message));
            app.StoredPacket = packet;
            app.PacketArea.Value = app.wrapPacketHex(packet);

            app.appendLogEntry(sprintf('User text accepted: %s', message));
            app.appendLogEntry(sprintf('AX.25 packet stored (%d bytes).', numel(packet)));
            app.InputField.Value = '';
        end

        function decodeStoredPacket(app)
            if isempty(app.StoredPacket)
                app.appendLogEntry('No stored AX.25 packet is available to depacketize.');
                return;
            end

            try
                decodedText = app.decodeAX25Packet(app.StoredPacket);
                app.appendLogEntry(sprintf('Depacketized text: %s', decodedText));
            catch exception
                app.appendLogEntry(sprintf('Depacketization failed: %s', exception.message));
            end
        end

        function modulateStoredPacket(app)
            if isempty(app.StoredPacket)
                app.appendLogEntry('No stored AX.25 packet is available to modulate.');
                return;
            end

            [waveform, timeAxis, frameBits] = app.createAFSKWaveform(app.StoredPacket);
            app.StoredWaveform = waveform;

            figure('Name', 'AFSK Modulated Signal', 'NumberTitle', 'off', 'Color', 'w');

            subplot(2, 1, 1);
            plot(timeAxis, waveform, 'b');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('AX.25 AFSK Waveform');

            zoomSampleCount = min(numel(waveform), 20 * 40);
            subplot(2, 1, 2);
            plot(timeAxis(1:zoomSampleCount), waveform(1:zoomSampleCount), 'r');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('Zoomed View (First 20 Bits)');

            app.appendLogEntry(sprintf( ...
                'AFSK waveform generated: %d bits, %d samples.', ...
                numel(frameBits), numel(waveform)));
        end

        function fmModulateStoredWaveform(app)
            if isempty(app.StoredWaveform)
                app.appendLogEntry('Generate the AFSK waveform before requesting FM modulation.');
                return;
            end

            [fmWaveform, timeAxis, sampleRate] = app.createFMWaveform(app.StoredWaveform);
            app.StoredFMWaveform = fmWaveform;
            app.StoredFMFilePath = fullfile(fileparts(mfilename('fullpath')), 'storedFMSignal.mat');
            savedWaveform = fmWaveform; %#ok<NASGU>
            save(app.StoredFMFilePath, 'savedWaveform', 'sampleRate');

            figure('Name', 'FM Modulated Signal', 'NumberTitle', 'off', 'Color', 'w');

            subplot(2, 1, 1);
            plot(timeAxis, fmWaveform, 'm');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('FM Modulated AFSK Signal');

            zoomSampleCount = min(numel(fmWaveform), 4000);
            subplot(2, 1, 2);
            plot(timeAxis(1:zoomSampleCount), fmWaveform(1:zoomSampleCount), 'k');
            grid on;
            xlabel('Time (s)');
            ylabel('Amplitude');
            title('Zoomed View of FM Waveform');

            app.appendLogEntry(sprintf('FM waveform generated: %d samples.', numel(fmWaveform)));
            app.appendLogEntry(sprintf('FM waveform saved to: %s', app.StoredFMFilePath));
        end

        function recoverTextFromFMSignal(app)
            if isempty(app.StoredFMFilePath) || ~isfile(app.StoredFMFilePath)
                app.appendLogEntry('No saved FM waveform was found. Generate FM modulation first.');
                return;
            end

            try
                savedData = load(app.StoredFMFilePath, 'savedWaveform', 'sampleRate');
                recoveredAFSK = app.demodulateFMSignal(savedData.savedWaveform, savedData.sampleRate);
                recoveredBits = app.demodulateAFSKBits(recoveredAFSK, savedData.sampleRate);
                recoveredPacket = app.extractPacketFromBits(recoveredBits);
                recoveredText = app.decodeAX25Packet(recoveredPacket);

                app.StoredPacket = recoveredPacket;
                app.PacketArea.Value = app.wrapPacketHex(recoveredPacket);
                app.appendLogEntry(sprintf('Recovered text from FM signal: %s', recoveredText));
            catch exception
                app.appendLogEntry(sprintf('FM recovery failed: %s', exception.message));
            end
        end

        function appendSystemMessage(app, message)
            app.LogArea.Value = {char(message)};
        end

        function appendLogEntry(app, message)
            timestamp = datestr(now, 'HH:MM:SS');
            newEntry = sprintf('[%s] System: %s', timestamp, char(message));
            currentValue = app.LogArea.Value;

            if ischar(currentValue)
                currentLines = {currentValue};
            elseif isstring(currentValue) || iscategorical(currentValue)
                currentLines = cellstr(currentValue);
            else
                currentLines = currentValue;
            end

            if isempty(currentLines) || isequal(currentLines, {'Waiting for messages...'})
                app.LogArea.Value = {newEntry};
            else
                app.LogArea.Value = [currentLines; {newEntry}];
            end
        end

        function packet = createAX25Packet(app, message)
            destinationAddress = app.encodeAddressField('APRS', 0, false);
            sourceAddress = app.encodeAddressField('GROUND', 0, true);
            controlField = uint8(hex2dec('03'));
            protocolId = uint8(hex2dec('F0'));
            infoField = uint8(message);

            frameWithoutFcs = [destinationAddress, sourceAddress, controlField, protocolId, infoField];
            fcs = app.computeFCS(frameWithoutFcs);
            packet = uint8([frameWithoutFcs, fcs]);
        end

        function message = decodeAX25Packet(app, packet)
            if numel(packet) < 18
                error('Packet is too short to be a valid AX.25 UI frame.');
            end

            receivedFcs = uint8(packet(end-1:end));
            frameWithoutFcs = uint8(packet(1:end-2));
            calculatedFcs = app.computeFCS(frameWithoutFcs);

            if ~isequal(receivedFcs, calculatedFcs)
                error('CRC check failed for the stored packet.');
            end

            controlField = frameWithoutFcs(15);
            protocolId = frameWithoutFcs(16);

            if controlField ~= hex2dec('03') || protocolId ~= hex2dec('F0')
                error('Stored packet is not an AX.25 UI text frame.');
            end

            infoField = frameWithoutFcs(17:end);
            message = char(infoField);
        end

        function addressField = encodeAddressField(~, callsign, ssid, isLast)
            normalized = upper(char(callsign));
            normalized = normalized(1:min(strlength(normalized), 6));
            padded = pad(normalized, 6);

            addressField = zeros(1, 7, 'uint8');
            for index = 1:6
                addressField(index) = bitshift(uint8(padded(index)), 1);
            end

            ssidByte = uint8(bitshift(uint8(ssid), 1) + bin2dec('01100000'));
            if isLast
                ssidByte = bitor(ssidByte, uint8(1));
            end
            addressField(7) = ssidByte;
        end

        function fcsBytes = computeFCS(~, data)
            crc = uint16(hex2dec('FFFF'));
            polynomial = uint16(hex2dec('8408'));

            for byte = uint8(data)
                crc = bitxor(crc, uint16(byte));
                for bitIndex = 1:8
                    if bitand(crc, uint16(1))
                        crc = bitxor(bitshift(crc, -1), polynomial);
                    else
                        crc = bitshift(crc, -1);
                    end
                end
            end

            crc = bitcmp(crc);
            lowByte = uint8(bitand(crc, uint16(255)));
            highByte = uint8(bitshift(crc, -8));
            fcsBytes = uint8([lowByte, highByte]);
        end

        function wrappedText = wrapPacketHex(~, packet)
            hexValues = upper(compose('%02X', packet));
            lineLength = 12;
            lineCount = ceil(numel(hexValues) / lineLength);
            wrappedText = cell(lineCount, 1);

            for lineIndex = 1:lineCount
                startIndex = (lineIndex - 1) * lineLength + 1;
                endIndex = min(lineIndex * lineLength, numel(hexValues));
                wrappedText{lineIndex} = strjoin(cellstr(hexValues(startIndex:endIndex)), ' ');
            end
        end

        function [waveform, timeAxis, frameBits] = createAFSKWaveform(app, packet)
            sampleRate = 48000;
            bitRate = 1200;
            markFrequency = 1200;
            spaceFrequency = 2200;
            samplesPerBit = sampleRate / bitRate;

            if abs(samplesPerBit - round(samplesPerBit)) > eps
                error('Sample rate must be an integer multiple of the bit rate.');
            end

            flagBytes = uint8([126 126 126]);
            flagBits = app.bytesToLSBFirstBits(flagBytes);
            payloadBits = app.bytesToLSBFirstBits(packet);
            stuffedPayloadBits = app.applyBitStuffing(payloadBits);
            frameBits = [flagBits, stuffedPayloadBits, app.bytesToLSBFirstBits(uint8(126))];

            bitCount = numel(frameBits);
            waveform = zeros(1, bitCount * samplesPerBit);
            phase = 0;
            currentFrequency = markFrequency;

            for bitIndex = 1:bitCount
                if frameBits(bitIndex) == 0
                    if currentFrequency == markFrequency
                        currentFrequency = spaceFrequency;
                    else
                        currentFrequency = markFrequency;
                    end
                end

                sampleIndices = (bitIndex - 1) * samplesPerBit + (1:samplesPerBit);
                localTime = (0:samplesPerBit - 1) / sampleRate;
                waveform(sampleIndices) = sin(2 * pi * currentFrequency * localTime + phase);
                phase = mod(phase + 2 * pi * currentFrequency * samplesPerBit / sampleRate, 2 * pi);
            end

            timeAxis = (0:numel(waveform) - 1) / sampleRate;
        end

        function [fmWaveform, timeAxis, sampleRate] = createFMWaveform(~, afskWaveform)
            sampleRate = 48000;
            carrierFrequency = 10000;
            frequencyDeviation = 3000;

            normalizedAFSK = afskWaveform ./ max(abs(afskWaveform) + eps);
            instantaneousPhase = 2 * pi * carrierFrequency * (0:numel(normalizedAFSK) - 1) / sampleRate;
            modulationPhase = 2 * pi * frequencyDeviation / sampleRate * cumsum(normalizedAFSK);
            fmWaveform = cos(instantaneousPhase + modulationPhase);
            timeAxis = (0:numel(fmWaveform) - 1) / sampleRate;
        end

        function recoveredAFSK = demodulateFMSignal(~, fmWaveform, sampleRate)
            carrierFrequency = 10000;
            frequencyDeviation = 3000;
            timeAxis = (0:numel(fmWaveform) - 1) / sampleRate;
            localCosine = cos(2 * pi * carrierFrequency * timeAxis);
            localSine = -sin(2 * pi * carrierFrequency * timeAxis);

            inPhase = fmWaveform .* localCosine;
            quadrature = fmWaveform .* localSine;

            filterLength = 16;
            averagingKernel = ones(1, filterLength) / filterLength;
            inPhase = conv(inPhase, averagingKernel, 'same');
            quadrature = conv(quadrature, averagingKernel, 'same');

            modulationPhase = unwrap(atan2(quadrature, inPhase));
            phaseDifference = [0, diff(modulationPhase)];
            recoveredAFSK = phaseDifference * sampleRate / (2 * pi * frequencyDeviation);

            maxValue = max(abs(recoveredAFSK));
            if maxValue > 0
                recoveredAFSK = recoveredAFSK / maxValue;
            end
        end

        function bits = demodulateAFSKBits(~, waveform, sampleRate)
            bitRate = 1200;
            markFrequency = 1200;
            spaceFrequency = 2200;
            samplesPerBit = round(sampleRate / bitRate);
            bitCount = floor(numel(waveform) / samplesPerBit);
            bits = zeros(1, bitCount);
            previousTone = markFrequency;

            for bitIndex = 1:bitCount
                sampleIndices = (bitIndex - 1) * samplesPerBit + (1:samplesPerBit);
                bitSamples = waveform(sampleIndices);
                localTime = (0:samplesPerBit - 1) / sampleRate;

                markMetric = abs(sum(bitSamples .* exp(-1j * 2 * pi * markFrequency * localTime)));
                spaceMetric = abs(sum(bitSamples .* exp(-1j * 2 * pi * spaceFrequency * localTime)));

                if markMetric >= spaceMetric
                    currentTone = markFrequency;
                else
                    currentTone = spaceFrequency;
                end

                if currentTone == previousTone
                    bits(bitIndex) = 1;
                else
                    bits(bitIndex) = 0;
                end

                previousTone = currentTone;
            end
        end

        function packet = extractPacketFromBits(app, bits)
            flagPattern = [0 1 1 1 1 1 1 0];
            flagStartIndices = app.findBitPattern(bits, flagPattern);

            if numel(flagStartIndices) < 2
                error('Unable to find AX.25 flag bytes in the recovered bit stream.');
            end

            openingFlagIndex = flagStartIndices(1);
            while numel(flagStartIndices) > 1 && flagStartIndices(2) == openingFlagIndex + 8
                flagStartIndices(1) = [];
                openingFlagIndex = flagStartIndices(1);
            end

            closingFlagIndex = flagStartIndices(end);
            payloadBits = bits(openingFlagIndex + 8:closingFlagIndex - 1);
            payloadBits = app.removeBitStuffing(payloadBits);

            fullByteCount = floor(numel(payloadBits) / 8);
            if fullByteCount == 0
                error('Recovered payload does not contain any full bytes.');
            end

            payloadBits = payloadBits(1:fullByteCount * 8);
            packet = app.bitsToBytesLSBFirst(payloadBits);
        end

        function indices = findBitPattern(~, bits, pattern)
            matchCount = numel(bits) - numel(pattern) + 1;
            indices = [];

            for startIndex = 1:matchCount
                if isequal(bits(startIndex:startIndex + numel(pattern) - 1), pattern)
                    indices(end + 1) = startIndex; %#ok<AGROW>
                end
            end
        end

        function bits = removeBitStuffing(~, stuffedBits)
            bits = zeros(1, numel(stuffedBits));
            outputIndex = 0;
            inputIndex = 1;
            consecutiveOnes = 0;

            while inputIndex <= numel(stuffedBits)
                currentBit = stuffedBits(inputIndex);
                outputIndex = outputIndex + 1;
                bits(outputIndex) = currentBit;

                if currentBit == 1
                    consecutiveOnes = consecutiveOnes + 1;
                    if consecutiveOnes == 5
                        inputIndex = inputIndex + 1;
                        consecutiveOnes = 0;
                    end
                else
                    consecutiveOnes = 0;
                end

                inputIndex = inputIndex + 1;
            end

            bits = bits(1:outputIndex);
        end

        function byteArray = bitsToBytesLSBFirst(~, bits)
            byteCount = numel(bits) / 8;
            byteArray = zeros(1, byteCount, 'uint8');

            for byteIndex = 1:byteCount
                baseIndex = (byteIndex - 1) * 8;
                byteValue = uint8(0);
                for bitIndex = 1:8
                    if bits(baseIndex + bitIndex) ~= 0
                        byteValue = bitor(byteValue, bitshift(uint8(1), bitIndex - 1));
                    end
                end
                byteArray(byteIndex) = byteValue;
            end
        end

        function bits = bytesToLSBFirstBits(~, byteArray)
            byteArray = uint8(byteArray);
            bits = zeros(1, numel(byteArray) * 8);

            for byteIndex = 1:numel(byteArray)
                byteValue = byteArray(byteIndex);
                baseIndex = (byteIndex - 1) * 8;
                for bitIndex = 1:8
                    bits(baseIndex + bitIndex) = bitget(byteValue, bitIndex);
                end
            end
        end

        function stuffedBits = applyBitStuffing(~, bits)
            stuffedBits = zeros(1, numel(bits) + floor(numel(bits) / 5));
            outputIndex = 0;
            consecutiveOnes = 0;

            for bitIndex = 1:numel(bits)
                outputIndex = outputIndex + 1;
                stuffedBits(outputIndex) = bits(bitIndex);

                if bits(bitIndex) == 1
                    consecutiveOnes = consecutiveOnes + 1;
                    if consecutiveOnes == 5
                        outputIndex = outputIndex + 1;
                        stuffedBits(outputIndex) = 0;
                        consecutiveOnes = 0;
                    end
                else
                    consecutiveOnes = 0;
                end
            end

            stuffedBits = stuffedBits(1:outputIndex);
        end
    end
end
