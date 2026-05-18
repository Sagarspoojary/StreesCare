import librosa
import numpy as np
import os

def extract_features(audio_path):
    try:
        # Load at fixed 16kHz sample rate for consistency
        y, sr = librosa.load(audio_path, sr=16000)

        # ✅ Normalize audio — CRITICAL for consistent RMS across devices/volumes
        y = librosa.util.normalize(y)

        # Extract waveform features
        rms = np.mean(librosa.feature.rms(y=y))
        zcr = np.mean(librosa.feature.zero_crossing_rate(y))
        centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))

        # Debug logs — confirms real audio is being processed
        print(f"DEBUG RMS: {rms:.6f}")
        print(f"DEBUG ZCR: {zcr:.6f}")
        print(f"DEBUG CENTROID: {centroid:.2f}")

        return {
            "energy": float(rms),
            "pitch_variation": float(zcr * 100), # Approximation of variation
            "speech_rate": float(centroid / 10)  # Approximation of pace
        }

    except Exception as e:
        import traceback
        print(f"AUDIO FEATURE ERROR: {e}")
        traceback.print_exc()
        return None


def detect_emotion_from_audio(features):
    if not features:
        return {
            "emotion": "neutral",
            "stress_level": "low",
            "burnout_score": 20
        }

    rms = features["rms"]
    zcr = features["zcr"]
    centroid = features.get("centroid", 0)

    # ✅ ADAPTIVE HEURISTIC (calibrated for normalized audio)
    # Stress: High energy (RMS) + High frequency/agitation (ZCR/Centroid)
    if rms > 0.05:
        # High ZCR (>0.12) or high spectral centroid (>2200) indicates agitation/stress
        if zcr > 0.12 or centroid > 2200:
            return {
                "emotion": "stress",
                "stress_level": "high",
                "burnout_score": 85
            }
        # High energy but lower frequency indicates active/normal engagement
        else:
            return {
                "emotion": "engagement",
                "stress_level": "medium",
                "burnout_score": 40
            }

    # Fatigue: Very low energy
    elif rms < 0.02:
        return {
            "emotion": "fatigue",
            "stress_level": "medium",
            "burnout_score": 60
        }

    # Baseline: Calm/Neutral range (0.02 - 0.05 RMS)
    else:
        return {
            "emotion": "neutral",
            "stress_level": "low",
            "burnout_score": 25
        }

import speech_recognition as sr

def transcribe_audio(audio_path: str) -> str:
    """
    Converts audio file to text using SpeechRecognition.
    """
    recognizer = sr.Recognizer()
    try:
        # We need to make sure it's in WAV format for SpeechRecognition
        # librosa can read many formats, but sr.AudioFile expects standard formats
        # We'll rely on the frontend sending WAV.
        with sr.AudioFile(audio_path) as source:
            audio_data = recognizer.record(source)
            text = recognizer.recognize_google(audio_data)
            return text
    except sr.UnknownValueError:
        return ""
    except sr.RequestError as e:
        print(f"Could not request results from Google Speech Recognition service; {e}")
        return ""
    except Exception as e:
        print(f"Transcription error: {e}")
        return ""
