# MATLAB Simple Chat GUI

This project now uses a simple and reliable two-system MATLAB chat over TCP/IP, focused only on getting text across systems.

## Files

- `launchChatGUI.m`: opens the transmitter app
- `launchReceiverGUI.m`: opens the receiver app
- `SimpleChatTransmitterGUI.m`: transmitter-side GUI
- `SimpleChatReceiverGUI.m`: receiver-side GUI

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

- transmitter app sends plain text to a receiver system using `tcpclient`
- receiver app listens on a chosen port using `tcpserver`
- receiver automatically prints text as soon as a message arrives
- sender only needs the receiver IP address and port
- default port is `55000`

## Notes

- Both systems should be on the same network and able to reach each other by IP.
- If Windows Firewall prompts for MATLAB network access, allow it on the receiver system.
- I could not run MATLAB in this environment, so you still need to test the actual network connection on your two systems.
