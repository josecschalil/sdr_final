# MATLAB Pluto Simple Chat

This project now uses a simpler Pluto SDR text modem so the transmitter and receiver still work through ADALM Pluto, but without the heavier AX.25/AFSK/FM chain.

## Files

- `launchChatGUI.m`: opens the transmitter app
- `launchReceiverGUI.m`: opens the receiver app
- `PlutoSimpleChatTransmitterGUI.m`: transmitter-side GUI
- `PlutoSimpleChatReceiverGUI.m`: receiver-side GUI
- `PlutoSimpleChatCodec.m`: shared simple packet/modem logic

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

- transmitter sends plain text as a simple OOK packet through ADALM Pluto
- receiver listens continuously and automatically prints text when a valid packet is recovered
- both sides include an SDR selection with `ADALM-PLUTO` and `Simulation File Loopback`
- both sides include the 3 frequency choices:
  `433.92 MHz ISM`, `915.00 MHz ISM`, `2400.00 MHz ISM`
- `Simulation File Loopback` is available for testing the full transmitter/receiver logic without radio hardware

## Notes

- This version is intentionally simpler than the previous modulation stack so the focus stays on getting text across two Pluto systems.
- I could not run MATLAB or test Pluto hardware in this environment, so live SDR testing still has to be done on your two systems.
