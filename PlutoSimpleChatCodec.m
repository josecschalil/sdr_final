classdef PlutoSimpleChatCodec
    % PlutoSimpleChatCodec Simple OOK packet modem for text chat over Pluto SDR.

    methods (Static)
        function settings = defaultSettings()
            settings = struct( ...
                'SampleRate', 1e6, ...
                'BitRate', 1000, ...
                'SamplesPerBit', 1000, ...
                'ToneFrequency', 100e3, ...
                'OneAmplitude', 0.9, ...
                'ZeroAmplitude', 0.0, ...
                'PlutoFrameLength', 250000, ...
                'PlutoTxGain', 0, ...
                'PlutoRxGain', 50, ...
                'PacketRepeats', 20, ...
                'InterPacketZeroBits', 24);
        end

        function options = frequencyOptions()
            options = { ...
                '433.92 MHz ISM', ...
                '915.00 MHz ISM', ...
                '2400.00 MHz ISM'};
        end

        function options = sdrOptions()
            options = {'ADALM-PLUTO', 'Simulation File Loopback'};
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

        function waveform = createTransmitWaveform(message)
            settings = PlutoSimpleChatCodec.defaultSettings();
            packetBits = PlutoSimpleChatCodec.createPacketBits(message);
            repeatedBits = [];
            zeroGap = zeros(1, settings.InterPacketZeroBits);

            for repeatIndex = 1:settings.PacketRepeats
                repeatedBits = [repeatedBits, packetBits, zeroGap]; %#ok<AGROW>
            end

            waveform = PlutoSimpleChatCodec.modulateOOK(repeatedBits);
        end

        function packetBits = createPacketBits(message)
            payloadBytes = uint8(unicode2native(char(message), 'UTF-8'));
            if numel(payloadBytes) > 200
                error('Message is too long. Keep it under 200 UTF-8 bytes.');
            end

            preambleBits = repmat([1 0], 1, 24);
            syncBits = PlutoSimpleChatCodec.bytesToBitsMSB(uint8([hex2dec('D3'), hex2dec('91')]));
            lengthBits = PlutoSimpleChatCodec.bytesToBitsMSB(uint8(numel(payloadBytes)));
            checksumByte = uint8(mod(sum(double(payloadBytes)), 256));
            checksumBits = PlutoSimpleChatCodec.bytesToBitsMSB(checksumByte);
            payloadBits = PlutoSimpleChatCodec.bytesToBitsMSB(payloadBytes);
            packetBits = [preambleBits, syncBits, lengthBits, payloadBits, checksumBits];
        end

        function waveform = modulateOOK(bits)
            settings = PlutoSimpleChatCodec.defaultSettings();
            samplesPerBit = settings.SamplesPerBit;
            totalSamples = numel(bits) * samplesPerBit;
            waveform = complex(zeros(totalSamples, 1));
            sampleTime = (0:samplesPerBit - 1)' / settings.SampleRate;
            tone = exp(1j * 2 * pi * settings.ToneFrequency * sampleTime);

            for bitIndex = 1:numel(bits)
                sampleIndices = (bitIndex - 1) * samplesPerBit + (1:samplesPerBit);
                if bits(bitIndex) == 1
                    waveform(sampleIndices) = settings.OneAmplitude * tone;
                else
                    waveform(sampleIndices) = settings.ZeroAmplitude * tone;
                end
            end
        end

        function [message, packetBits] = recoverMessage(receivedSamples)
            settings = PlutoSimpleChatCodec.defaultSettings();
            matchedSignal = receivedSamples(:) .* exp(-1j * 2 * pi * settings.ToneFrequency * (0:numel(receivedSamples) - 1)' / settings.SampleRate);
            envelope = abs(matchedSignal);
            envelope = conv(envelope, ones(settings.SamplesPerBit, 1) / settings.SamplesPerBit, 'same');
            [bitStream, metrics] = PlutoSimpleChatCodec.sampleBitsAcrossOffsets(envelope);
            packetBits = PlutoSimpleChatCodec.findValidPacket(bitStream, metrics);
            message = PlutoSimpleChatCodec.decodePacketBits(packetBits);
        end

        function saveWaveform(filePath, waveform, centerFrequency)
            settings = PlutoSimpleChatCodec.defaultSettings();
            savedWaveform = waveform; %#ok<NASGU>
            metadata = struct( ...
                'SampleRate', settings.SampleRate, ...
                'CenterFrequency', centerFrequency, ...
                'SavedAt', char(datetime('now'))); %#ok<NASGU>
            save(filePath, 'savedWaveform', 'metadata');
        end

        function payload = loadWaveform(filePath)
            payload = load(filePath, 'savedWaveform', 'metadata');
        end

        function transmit(selection, centerFrequency, waveform, filePath)
            settings = PlutoSimpleChatCodec.defaultSettings();

            switch char(selection)
                case 'ADALM-PLUTO'
                    tx = sdrtx('Pluto', ...
                        'CenterFrequency', centerFrequency, ...
                        'BasebandSampleRate', settings.SampleRate, ...
                        'Gain', settings.PlutoTxGain);
                    tx(waveform);
                    release(tx);
                case 'Simulation File Loopback'
                    PlutoSimpleChatCodec.saveWaveform(filePath, waveform, centerFrequency);
                otherwise
                    error('Unsupported SDR selection.');
            end
        end

        function rx = createReceiver(centerFrequency)
            settings = PlutoSimpleChatCodec.defaultSettings();
            rx = sdrrx('Pluto', ...
                'CenterFrequency', centerFrequency, ...
                'BasebandSampleRate', settings.SampleRate, ...
                'SamplesPerFrame', settings.PlutoFrameLength, ...
                'GainSource', 'Manual', ...
                'Gain', settings.PlutoRxGain, ...
                'OutputDataType', 'double');
        end
    end

    methods (Static, Access = private)
        function [bestBitStream, bestMetrics] = sampleBitsAcrossOffsets(envelope)
            settings = PlutoSimpleChatCodec.defaultSettings();
            bestBitStream = zeros(1, 0);
            bestMetrics = zeros(1, 0);
            bestScore = -Inf;

            for offset = 0:settings.SamplesPerBit - 1
                startIndex = offset + 1;
                if startIndex > numel(envelope)
                    continue;
                end

                trimmedEnvelope = envelope(startIndex:end);
                bitCount = floor(numel(trimmedEnvelope) / settings.SamplesPerBit);
                if bitCount < 40
                    continue;
                end

                metrics = zeros(1, bitCount);
                for bitIndex = 1:bitCount
                    sampleIndices = (bitIndex - 1) * settings.SamplesPerBit + (1:settings.SamplesPerBit);
                    metrics(bitIndex) = mean(trimmedEnvelope(sampleIndices));
                end

                score = max(metrics) - min(metrics);
                if score > bestScore
                    threshold = 0.5 * (max(metrics) + min(metrics));
                    bestBitStream = metrics > threshold;
                    bestMetrics = metrics;
                    bestScore = score;
                end
            end

            if isempty(bestBitStream)
                error('Not enough samples were captured to recover a bit stream.');
            end
        end

        function packetBits = findValidPacket(bitStream, metrics)
            syncBits = PlutoSimpleChatCodec.bytesToBitsMSB(uint8([hex2dec('D3'), hex2dec('91')]));
            syncIndices = PlutoSimpleChatCodec.findPattern(bitStream, syncBits);

            if isempty(syncIndices)
                error('No sync word was detected in the received bit stream.');
            end

            for syncIndex = syncIndices
                lengthStart = syncIndex + numel(syncBits);
                lengthEnd = lengthStart + 7;
                if lengthEnd > numel(bitStream)
                    continue;
                end

                lengthByte = PlutoSimpleChatCodec.bitsToBytesMSB(bitStream(lengthStart:lengthEnd));
                payloadLength = double(lengthByte);
                payloadBitCount = payloadLength * 8;
                payloadStart = lengthEnd + 1;
                payloadEnd = payloadStart + payloadBitCount - 1;
                checksumStart = payloadEnd + 1;
                checksumEnd = checksumStart + 7;

                if checksumEnd > numel(bitStream)
                    continue;
                end

                candidateBits = bitStream(syncIndex:checksumEnd);
                payloadBytes = PlutoSimpleChatCodec.bitsToBytesMSB(bitStream(payloadStart:payloadEnd));
                checksumByte = PlutoSimpleChatCodec.bitsToBytesMSB(bitStream(checksumStart:checksumEnd));
                expectedChecksum = uint8(mod(sum(double(payloadBytes)), 256));

                if checksumByte == expectedChecksum
                    metricWindow = metrics(syncIndex:checksumEnd);
                    if max(metricWindow) - min(metricWindow) > 0.05
                        packetBits = candidateBits;
                        return;
                    end
                end
            end

            error('No checksum-valid packet was found in the received stream.');
        end

        function message = decodePacketBits(packetBits)
            syncLength = 16;
            lengthBits = packetBits(syncLength + 1:syncLength + 8);
            payloadLength = double(PlutoSimpleChatCodec.bitsToBytesMSB(lengthBits));
            payloadStart = syncLength + 9;
            payloadEnd = payloadStart + payloadLength * 8 - 1;
            payloadBytes = PlutoSimpleChatCodec.bitsToBytesMSB(packetBits(payloadStart:payloadEnd));
            message = native2unicode(payloadBytes, 'UTF-8');
        end

        function bits = bytesToBitsMSB(byteArray)
            byteArray = uint8(byteArray);
            bits = zeros(1, numel(byteArray) * 8);

            for byteIndex = 1:numel(byteArray)
                byteValue = byteArray(byteIndex);
                baseIndex = (byteIndex - 1) * 8;
                for bitIndex = 1:8
                    bits(baseIndex + bitIndex) = bitget(byteValue, 9 - bitIndex);
                end
            end
        end

        function byteArray = bitsToBytesMSB(bits)
            byteCount = numel(bits) / 8;
            byteArray = zeros(1, byteCount, 'uint8');

            for byteIndex = 1:byteCount
                baseIndex = (byteIndex - 1) * 8;
                byteValue = uint8(0);
                for bitIndex = 1:8
                    if bits(baseIndex + bitIndex) ~= 0
                        byteValue = bitor(byteValue, bitshift(uint8(1), 8 - bitIndex));
                    end
                end
                byteArray(byteIndex) = byteValue;
            end
        end

        function indices = findPattern(bitStream, pattern)
            matchCount = numel(bitStream) - numel(pattern) + 1;
            indices = [];

            for startIndex = 1:matchCount
                if isequal(bitStream(startIndex:startIndex + numel(pattern) - 1), pattern)
                    indices(end + 1) = startIndex; %#ok<AGROW>
                end
            end
        end
    end
end
