# Bit Perfect Playback over fallback output

VCO Player treats Bit Perfect Playback as the primary product constraint. The player must preserve the decoded source format through the CoreAudio output path, so playback fails explicitly when the selected output device or audio path cannot avoid system mixing, sample-rate conversion, bit-depth conversion, software volume, or automatic device fallback.
