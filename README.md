# MATLAB SDR Chat GUI

This project now includes separate transmitter-side and receiver-side MATLAB apps for a digital chat system built around the path:

`AX.25 -> AFSK -> FM -> SDR -> FM -> AFSK -> AX.25 -> text`

## Files

- `launchChatGUI.m`: opens the transmitter app
- `launchReceiverGUI.m`: opens the receiver app
- `ChatTransmitterGUI.m`: transmitter-side GUI
- `ChatReceiverGUI.m`: receiver-side GUI
- `ChatSignalProcessor.m`: shared packet/modulation/demodulation helpers

## Run

On the transmitter system, open MATLAB in this folder and run:

```matlab
launchChatGUI
```

On the receiver system, run:

```matlab
launchReceiverGUI
```

## Current behavior

- transmitter UI accepts typed text and builds an AX.25 packet
- transmitter modulates the packet as AFSK and then FM
- transmitter shows an SDR dropdown with 3 options:
  `ADALM-PLUTO`, `Simulation File Loopback`, `No SDR (Signal Demo)`
- transmitter shows 3 selectable frequency ranges:
  `433.92 MHz ISM`, `915.00 MHz ISM`, `2400.00 MHz ISM`
- transmitter saves the FM waveform to `storedFMSignal.mat`
- transmitter can attempt to send the FM waveform through ADALM-Pluto using MATLAB SDR support
- receiver UI shows the same SDR dropdown and frequency dropdown
- receiver can start a background listening loop and automatically display text when a new packet arrives
- receiver can still perform a one-time manual receive for debugging
- receiver loads or receives FM data, demodulates it, recovers the AX.25 packet, and displays the recovered text

## Notes

- The Pluto SDR path assumes the MATLAB Communications Toolbox Support Package for Analog Devices ADALM-PLUTO Radio is installed.
- I could not run MATLAB or validate live Pluto hardware in this environment, so hardware testing still needs to be done on your systems.
- `Simulation File Loopback` is included so you can test the end-to-end logic without SDR hardware.
