# SampleFlutter
Project contains simple/easy to use SIP VoIP Client application for Windows/Linux/Mac/Android/iOS.
As SIP engine it uses Siprix SDK, included in binary form.

Application (Siprix) has ability to:

- Add SIP account
- Send/receive multiple calls
- Manage calls with:
   - Mute microphone/camera
   - Play sound to call from mp3 file
   - Record received sound to file
   - Send/receive DTMF
   - Transfer
   - ...

Application's UI may not contain all the features, available in the SDK, they will be added later.

## Limitations

Siprix doesn't have any limitations and can work with all existing servers (PBX) supported SIP.
For testing app you need an account(s) credentials from a SIP service provider(s).
Some features may be not supported by all SIP providers.

Included Siprix SDK works in trial mode and has limited call duration - it drops call after 60sec.
Upgrading to a paid license removes this restriction, enabling calls of any length.

Please contact [sales@siprix-voip.com](mailto:sales@siprix-voip.com) for more details.

## More resources

Product web site: https://siprix-voip.com

Manual: https://docs.siprix-voip.com


## Screenshots

<a href="https://docs.siprix-voip.com/screenshots/SampleFlutter_Android_Register.jpg"  title="Register account">
<img src="https://docs.siprix-voip.com/screenshots/SampleFlutter_Android_RegisterMini.jpg" width="50"></a>
<a href="https://docs.siprix-voip.com/screenshots/SampleFlutter_Android_ManageAccount.jpg"  title="Manage account">
<img src="https://docs.siprix-voip.com/screenshots/SampleFlutter_Android_ManageAccountMini.jpg" width="50"></a>
<a href="https://docs.siprix-voip.com/screenshots/SampleFlutter_Android_Call.jpg"  title="Call in progress">
<img src="https://docs.siprix-voip.com/screenshots/SampleFlutter_Android_CallMini.jpg" width="50"></a>
