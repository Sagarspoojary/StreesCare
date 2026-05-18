import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:io';

Widget buildWaveformPlayer(String audioUrl, Color primaryColor, Color surfaceColor) {
  return _MobileWaveformPlayer(
    audioUrl: audioUrl,
    primaryColor: primaryColor,
    surfaceColor: surfaceColor,
  );
}

class _MobileWaveformPlayer extends StatefulWidget {
  final String audioUrl;
  final Color primaryColor;
  final Color surfaceColor;

  const _MobileWaveformPlayer({
    Key? key,
    required this.audioUrl,
    required this.primaryColor,
    required this.surfaceColor,
  }) : super(key: key);

  @override
  State<_MobileWaveformPlayer> createState() => _MobileWaveformPlayerState();
}

class _MobileWaveformPlayerState extends State<_MobileWaveformPlayer> {
  late PlayerController controller;
  bool isPlaying = false;

  @override
  void initState() {
    super.initState();
    controller = PlayerController();
    _preparePlayer();
  }

  Future<void> _preparePlayer() async {
    try {
      // audioUrl is a local file path on mobile
      await controller.preparePlayer(
        path: widget.audioUrl,
        shouldExtractWaveform: true,
        noOfSamples: 100,
        volume: 1.0,
      );
      
      controller.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            isPlaying = state == PlayerState.playing;
          });
        }
      });
      
      controller.onCompletion.listen((_) {
        if (mounted) {
          setState(() {
            isPlaying = false;
          });
        }
      });
    } catch (e) {
      debugPrint("Error preparing player: $e");
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (isPlaying) {
      await controller.pausePlayer();
    } else {
      await controller.startPlayer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 65,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.surfaceColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.primaryColor.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Play/Pause Toggle Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: _togglePlay,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: widget.primaryColor,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Waveform View
          Expanded(
            child: AudioFileWaveforms(
              size: const Size(double.infinity, 40),
              playerController: controller,
              enableSeekGesture: true,
              waveformType: WaveformType.fitWidth,
              playerWaveStyle: PlayerWaveStyle(
                fixedWaveColor: widget.primaryColor.withOpacity(0.3),
                liveWaveColor: widget.primaryColor,
                spacing: 4,
                waveThickness: 2.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
