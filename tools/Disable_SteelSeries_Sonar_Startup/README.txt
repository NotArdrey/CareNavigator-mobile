Disable SteelSeries Sonar Startup
=================================

This package disables only these two output endpoints:

  SteelSeries Sonar - Gaming (SteelSeries Sonar Virtual Audio Device)
  SteelSeries Sonar - Chat (SteelSeries Sonar Virtual Audio Device)

It keeps both exact Microphone endpoints enabled and makes the Capture/input
endpoint the default microphone. The Microphone Render/output endpoint is not
disabled:

  SteelSeries Sonar - Microphone (SteelSeries Sonar Virtual Audio Device)

After disabling Sonar, it explicitly sets this exact device as the default
playback device:

  XG27ACS (NVIDIA High Definition Audio)

It does not disable XG27ACS, speakers, a headset, HyperX Microphone, NVIDIA
Broadcast, or any other audio device.

How it works
------------

The helper exports SoundVolumeView's device list, looks for exact matches, and
then sends /Disable only using the Gaming/Chat output rows' Command-Line
Friendly IDs. It sends /Enable for both exact Microphone rows, /SetDefault ...
all for the Microphone Capture row, and separately sends /SetDefault ... all
for the exact XG27ACS row. If a name is missing, renamed, or otherwise
ambiguous, the package takes no action for that name.

Setup
-----

1. Extract this folder somewhere permanent, for example:
   C:\Tools\Disable_SteelSeries_Sonar
2. Download SoundVolumeView from NirSoft:
   https://www.nirsoft.net/utils/soundvolumeview.html
3. Put SoundVolumeView.exe directly in this folder.
4. Run Disable_SteelSeries_Sonar.bat once to test. Its window is visible and
   reports which exact names were found, disabled, enabled, and selected as
   defaults.
5. Run Install_Startup.bat. The hidden one-shot waits 10 seconds after the
   next sign-in, executes once, waits another 10 seconds, executes a second
   confirming pass, and exits.

Other commands
--------------

  Enable_SteelSeries_Sonar.bat
    Stops the active one-shot and enables Gaming, Chat, and both exact
    Microphone endpoints; it also restores the Sonar Capture endpoint as the
    default microphone.
    Run Install_Startup.bat again if automatic disabling should resume.

  Set_XG27ACS_Default.bat
    Selects only the exact XG27ACS device as the default playback device.

  Uninstall_Startup.bat
    Removes the Startup shortcut and asks an already-running one-shot to stop.
    It leaves this package in place.

If SteelSeries GG or an application recreates the devices later, run
Disable_SteelSeries_Sonar.bat manually again.

Important
---------

If SteelSeries changes any device name, this package will report "Not found;
no action taken" for that name. It will not substitute another audio device.
The SoundVolumeView executable is not included; download it from NirSoft and
place it beside the scripts.
