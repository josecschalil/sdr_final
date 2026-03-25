classdef ChatSignalProcessor
    % ChatSignalProcessor Shared signal-chain helpers for the chat apps.

    methods (Static)
        function settings = defaultSettings()
            settings = struct( ...
                'SampleRate', 96000, ...
                'BitRate', 1200, ...
                'MarkFrequency', 1200, ...
                'SpaceFrequency', 2200, ...
                'FMFrequencyDeviation', 3000, ...
                'PlutoBasebandSampleRate', 96000, ...
                'PlutoFrameLength', 65536, ...
                'PlutoBurstRepeats', 12, ...
                'PlutoTxGain', 0, ...
                'PlutoRxGain', 50, ...
                'AX25PreambleFlags', 32, ...
                'AX25PostambleFlags', 4);
        end

        function packet = createAX25Packet(message)
            destinationAddress = ChatSignalProcessor.encodeAddressField('APRS', 0, false);
            sourceAddress = ChatSignalProcessor.encodeAddressField('GROUND', 0, true);
            controlField = uint8(hex2dec('03'));
            protocolId = uint8(hex2dec('F0'));
            infoField = uint8(char(message));
            frameWithoutFcs = [destinationAddress, sourceAddress, controlField, protocolId, infoField];
            fcs = ChatSignalProcessor.computeFCS(frameWithoutFcs);
            packet = uint8([frameWithoutFcs, fcs]);
        end

        function message = decodeAX25Packet(packet)
            if numel(packet) < 18
                error('Packet is too short to be a valid AX.25 UI frame.');
            end

            receivedFcs = uint8(packet(end-1:end));
            frameWithoutFcs = uint8(packet(1:end-2));
            calculatedFcs = ChatSignalProcessor.computeFCS(frameWithoutFcs);

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

        function [waveform, timeAxis, frameBits] = createAFSKWaveform(packet)
            settings = ChatSignalProcessor.defaultSettings();
            samplesPerBit = settings.SampleRate / settings.BitRate;

            if abs(samplesPerBit - round(samplesPerBit)) > eps
                error('Sample rate must be an integer multiple of the bit rate.');
            end

            preambleFlags = repmat(uint8(126), 1, settings.AX25PreambleFlags);
            postambleFlags = repmat(uint8(126), 1, settings.AX25PostambleFlags);
            flagBits = ChatSignalProcessor.bytesToLSBFirstBits(preambleFlags);
            payloadBits = ChatSignalProcessor.bytesToLSBFirstBits(packet);
            stuffedPayloadBits = ChatSignalProcessor.applyBitStuffing(payloadBits);
            frameBits = [flagBits, stuffedPayloadBits, ChatSignalProcessor.bytesToLSBFirstBits(postambleFlags)];

            bitCount = numel(frameBits);
            waveform = zeros(1, bitCount * samplesPerBit);
            phase = 0;
            currentFrequency = settings.MarkFrequency;

            for bitIndex = 1:bitCount
                if frameBits(bitIndex) == 0
                    if currentFrequency == settings.MarkFrequency
                        currentFrequency = settings.SpaceFrequency;
                    else
                        currentFrequency = settings.MarkFrequency;
                    end
                end

                sampleIndices = (bitIndex - 1) * samplesPerBit + (1:samplesPerBit);
                localTime = (0:samplesPerBit - 1) / settings.SampleRate;
                waveform(sampleIndices) = sin(2 * pi * currentFrequency * localTime + phase);
                phase = mod(phase + 2 * pi * currentFrequency * samplesPerBit / settings.SampleRate, 2 * pi);
            end

            timeAxis = (0:numel(waveform) - 1) / settings.SampleRate;
        end

        function [fmWaveform, timeAxis, sampleRate] = createFMWaveform(afskWaveform)
            settings = ChatSignalProcessor.defaultSettings();
            sampleRate = settings.SampleRate;
            normalizedAFSK = afskWaveform ./ max(abs(afskWaveform) + eps);
            modulationPhase = 2 * pi * settings.FMFrequencyDeviation / sampleRate * cumsum(normalizedAFSK);
            fmWaveform = exp(1j * modulationPhase);
            timeAxis = (0:numel(fmWaveform) - 1) / sampleRate;
        end

        function recoveredAFSK = demodulateFMSignal(fmWaveform, sampleRate)
            settings = ChatSignalProcessor.defaultSettings();
            if isempty(fmWaveform)
                recoveredAFSK = [];
                return;
            end

            if isreal(fmWaveform)
                analyticSignal = complex(fmWaveform, zeros(size(fmWaveform)));
            else
                analyticSignal = fmWaveform;
            end

            phaseStep = angle(analyticSignal(2:end) .* conj(analyticSignal(1:end-1)));
            recoveredAFSK = [0, phaseStep] * sampleRate / (2 * pi * settings.FMFrequencyDeviation);

            % Smooth the discriminator output to reduce jitter in noisy captures.
            recoveredAFSK = conv(recoveredAFSK, ones(1, 5) / 5, 'same');
            recoveredAFSK = recoveredAFSK - mean(recoveredAFSK);
            maxValue = max(abs(recoveredAFSK));
            if maxValue > 0
                recoveredAFSK = recoveredAFSK / maxValue;
            end
        end

        function bits = demodulateAFSKBits(waveform, sampleRate, sampleOffset)
            settings = ChatSignalProcessor.defaultSettings();
            if nargin < 3
                sampleOffset = 0;
            end

            samplesPerBit = round(sampleRate / settings.BitRate);
            startSample = sampleOffset + 1;
            if startSample > numel(waveform)
                bits = zeros(1, 0);
                return;
            end

            trimmedWaveform = waveform(startSample:end);
            bitCount = floor(numel(trimmedWaveform) / samplesPerBit);
            bits = zeros(1, bitCount);
            [markTone, spaceTone] = ChatSignalProcessor.estimateAFSKTones(trimmedWaveform, sampleRate, settings.MarkFrequency, settings.SpaceFrequency);
            previousTone = markTone;

            for bitIndex = 1:bitCount
                sampleIndices = (bitIndex - 1) * samplesPerBit + (1:samplesPerBit);
                bitSamples = trimmedWaveform(sampleIndices);
                localTime = (0:samplesPerBit - 1) / sampleRate;

                markMetric = abs(sum(bitSamples .* exp(-1j * 2 * pi * markTone * localTime)));
                spaceMetric = abs(sum(bitSamples .* exp(-1j * 2 * pi * spaceTone * localTime)));

                if markMetric >= spaceMetric
                    currentTone = markTone;
                else
                    currentTone = spaceTone;
                end

                if currentTone == previousTone
                    bits(bitIndex) = 1;
                else
                    bits(bitIndex) = 0;
                end

                previousTone = currentTone;
            end
        end

        function packet = extractPacketFromBits(bits)
            flagPattern = [0 1 1 1 1 1 1 0];
            flagStartIndices = ChatSignalProcessor.findBitPattern(bits, flagPattern);

            if numel(flagStartIndices) < 2
                error('Unable to find AX.25 flag bytes in the recovered bit stream.');
            end

            minPacketBytes = 18;
            maxPacketBytes = 512;
            for startIdx = 1:numel(flagStartIndices) - 1
                for endIdx = startIdx + 1:numel(flagStartIndices)
                    openingFlagIndex = flagStartIndices(startIdx);
                    closingFlagIndex = flagStartIndices(endIdx);
                    payloadBitCount = closingFlagIndex - (openingFlagIndex + 8);

                    if payloadBitCount < minPacketBytes * 8
                        continue;
                    end

                    if payloadBitCount > maxPacketBytes * 10
                        break;
                    end

                    payloadBits = bits(openingFlagIndex + 8:closingFlagIndex - 1);
                    payloadBits = ChatSignalProcessor.removeBitStuffing(payloadBits);
                    fullByteCount = floor(numel(payloadBits) / 8);

                    if fullByteCount < minPacketBytes || fullByteCount > maxPacketBytes
                        continue;
                    end

                    candidateBits = payloadBits(1:fullByteCount * 8);
                    candidatePacket = ChatSignalProcessor.bitsToBytesLSBFirst(candidateBits);

                    try
                        ChatSignalProcessor.decodeAX25Packet(candidatePacket);
                        packet = candidatePacket;
                        return;
                    catch
                    end
                end
            end

            error('Unable to recover a CRC-valid AX.25 packet from the bit stream.');
        end

        function packet = recoverPacketFromFMWaveform(fmWaveform, sampleRate)
            settings = ChatSignalProcessor.defaultSettings();
            recoveredAFSK = ChatSignalProcessor.demodulateFMSignal(fmWaveform, sampleRate);
            samplesPerBit = round(sampleRate / settings.BitRate);
            maxOffset = max(samplesPerBit - 1, 0);

            for sampleOffset = 0:maxOffset
                bits = ChatSignalProcessor.demodulateAFSKBits(recoveredAFSK, sampleRate, sampleOffset);
                if numel(bits) < 8 * 18
                    continue;
                end

                try
                    packet = ChatSignalProcessor.extractPacketFromBits(bits);
                    return;
                catch
                end
            end

            error('No valid AX.25 packet was recovered across tested symbol offsets.');
        end

        function hexLines = wrapPacketHex(packet)
            hexValues = upper(compose('%02X', uint8(packet)));
            lineLength = 12;
            lineCount = ceil(numel(hexValues) / lineLength);
            hexLines = cell(lineCount, 1);

            for lineIndex = 1:lineCount
                startIndex = (lineIndex - 1) * lineLength + 1;
                endIndex = min(lineIndex * lineLength, numel(hexValues));
                hexLines{lineIndex} = strjoin(cellstr(hexValues(startIndex:endIndex)), ' ');
            end
        end

        function saveFMToFile(filePath, fmWaveform, sampleRate, centerFrequency, sourceText)
            savedWaveform = fmWaveform; %#ok<NASGU>
            metadata = struct( ...
                'SampleRate', sampleRate, ...
                'CenterFrequency', centerFrequency, ...
                'CreatedAt', char(datetime('now')), ...
                'SourceText', char(sourceText)); %#ok<NASGU>
            save(filePath, 'savedWaveform', 'metadata');
        end

        function payload = loadFMFromFile(filePath)
            payload = load(filePath, 'savedWaveform', 'metadata');
        end

        function options = sdrOptions()
            options = {'ADALM-PLUTO', 'Simulation File Loopback', 'No SDR (Signal Demo)'};
        end

        function options = frequencyOptions()
            options = { ...
                '433.92 MHz ISM', ...
                '915.00 MHz ISM', ...
                '2400.00 MHz ISM'};
        end

        function centerFrequency = frequencyFromLabel(label)
            switch char(label)
                case '433.92 MHz ISM'
                    centerFrequency = 433.92e6;
                case '915.00 MHz ISM'
                    centerFrequency = 915.00e6;
                case '2400.00 MHz ISM'
                    centerFrequency = 2400.00e6;
                otherwise
                    error('Unsupported frequency selection.');
            end
        end

        function transmitViaSelectedSDR(selection, centerFrequency, fmWaveform, filePath)
            settings = ChatSignalProcessor.defaultSettings();

            switch char(selection)
                case 'ADALM-PLUTO'
                    tx = sdrtx('Pluto', ...
                        'CenterFrequency', centerFrequency, ...
                        'BasebandSampleRate', settings.PlutoBasebandSampleRate, ...
                        'Gain', settings.PlutoTxGain);
                    repeatedWaveform = repmat(fmWaveform(:), settings.PlutoBurstRepeats, 1);
                    tx(repeatedWaveform);
                    release(tx);
                case 'Simulation File Loopback'
                    ChatSignalProcessor.saveFMToFile(filePath, fmWaveform, settings.SampleRate, centerFrequency, '');
                case 'No SDR (Signal Demo)'
                    % Keep the waveform in app memory only.
                otherwise
                    error('Unsupported SDR selection.');
            end
        end

        function [fmWaveform, sampleRate] = receiveViaSelectedSDR(selection, centerFrequency, filePath)
            settings = ChatSignalProcessor.defaultSettings();

            switch char(selection)
                case 'ADALM-PLUTO'
                    rx = sdrrx('Pluto', ...
                        'CenterFrequency', centerFrequency, ...
                        'BasebandSampleRate', settings.PlutoBasebandSampleRate, ...
                        'SamplesPerFrame', settings.PlutoFrameLength, ...
                        'OutputDataType', 'double');
                    receivedSamples = rx();
                    release(rx);
                    fmWaveform = real(receivedSamples(:)).';
                    sampleRate = settings.SampleRate;
                case 'Simulation File Loopback'
                    loaded = ChatSignalProcessor.loadFMFromFile(filePath);
                    fmWaveform = loaded.savedWaveform;
                    sampleRate = loaded.metadata.SampleRate;
                case 'No SDR (Signal Demo)'
                    loaded = ChatSignalProcessor.loadFMFromFile(filePath);
                    fmWaveform = loaded.savedWaveform;
                    sampleRate = loaded.metadata.SampleRate;
                otherwise
                    error('Unsupported SDR selection.');
            end
        end
    end

    methods (Static, Access = private)
        function addressField = encodeAddressField(callsign, ssid, isLast)
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

        function fcsBytes = computeFCS(data)
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

        function bits = bytesToLSBFirstBits(byteArray)
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

        function stuffedBits = applyBitStuffing(bits)
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

        function indices = findBitPattern(bits, pattern)
            matchCount = numel(bits) - numel(pattern) + 1;
            indices = [];

            for startIndex = 1:matchCount
                if isequal(bits(startIndex:startIndex + numel(pattern) - 1), pattern)
                    indices(end + 1) = startIndex; %#ok<AGROW>
                end
            end
        end

        function bits = removeBitStuffing(stuffedBits)
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

        function byteArray = bitsToBytesLSBFirst(bits)
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

        function [markTone, spaceTone] = estimateAFSKTones(waveform, sampleRate, defaultMark, defaultSpace)
            markTone = defaultMark;
            spaceTone = defaultSpace;

            if isempty(waveform)
                return;
            end

            maxSamples = min(numel(waveform), 131072);
            segment = waveform(1:maxSamples);
            nfft = 2^nextpow2(maxSamples);
            spectrum = abs(fft(segment, nfft)).^2;
            frequencyAxis = (0:nfft - 1) * sampleRate / nfft;

            halfCount = floor(nfft / 2);
            spectrum = spectrum(1:halfCount);
            frequencyAxis = frequencyAxis(1:halfCount);

            candidateMask = frequencyAxis >= 500 & frequencyAxis <= 4000;
            if ~any(candidateMask)
                return;
            end

            candidateFrequencies = frequencyAxis(candidateMask);
            candidateSpectrum = spectrum(candidateMask);
            [~, sortedIndices] = sort(candidateSpectrum, 'descend');
            peakCount = min(30, numel(sortedIndices));
            peakFrequencies = candidateFrequencies(sortedIndices(1:peakCount));
            peakPowers = candidateSpectrum(sortedIndices(1:peakCount));

            bestScore = -Inf;
            for i = 1:peakCount
                for j = i + 1:peakCount
                    f1 = peakFrequencies(i);
                    f2 = peakFrequencies(j);
                    separation = abs(f2 - f1);
                    if separation < 700 || separation > 1300
                        continue;
                    end

                    score = peakPowers(i) + peakPowers(j) - abs(separation - 1000);
                    if score > bestScore
                        bestScore = score;
                        markTone = min(f1, f2);
                        spaceTone = max(f1, f2);
                    end
                end
            end
        end
    end
end
