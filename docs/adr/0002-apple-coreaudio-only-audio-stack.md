# Apple CoreAudio-only audio stack

VCO Player is macOS-only and uses Apple CoreAudio for the MVP audio stack instead of adding cross-platform playback backends or third-party decoders such as FFmpeg. This narrows format coverage and portability, but keeps the first implementation focused on the platform audio path needed for Bit Perfect Playback and makes unsupported formats fail explicitly rather than being decoded through an alternate path.
