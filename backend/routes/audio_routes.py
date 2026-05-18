from fastapi import APIRouter, UploadFile, File, Header, HTTPException
from fastapi.responses import JSONResponse
import shutil
import os
import uuid
import datetime
from typing import Optional

from utils.audio_emotion import extract_features, transcribe_audio, detect_emotion_from_audio
from utils.gemini_ai import get_emotional_response
from utils.pii_masking import mask_pii
from routes.chat_routes import get_user_from_token
from config.database import db

router = APIRouter(tags=["Audio"])

UPLOAD_DIR = "temp_audio"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@router.post("/audio/analyze")
async def analyze_audio(
    file: UploadFile = File(...),
    authorization: Optional[str] = Header(None)
):
    """
    Complete AI Voice Analysis Pipeline:
    VOICE INPUT -> Speech-to-Text -> PII Masking -> Emotion Analysis -> Gemini Response
    """
    user = get_user_from_token(authorization)
    user_id = user.get("user_id")

    file_path = ""
    try:
        ext = os.path.splitext(file.filename)[1] or ".wav"
        unique_filename = f"{uuid.uuid4()}{ext}"
        file_path = os.path.join(UPLOAD_DIR, unique_filename)

        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # 1. Extract Waveform Features
        features = extract_features(file_path)
        if not features:
            features = {"energy": 0, "pitch_variation": 0, "speech_rate": 0}

        # 2. Transcribe Audio
        transcription = transcribe_audio(file_path)
        if not transcription:
            transcription = "(Unintelligible audio)"

        # 3. PII Masking
        masked_text = mask_pii(transcription)

        # 4. Separate Vocal Emotion Detection (based ONLY on acoustics)
        acoustic_analysis = detect_emotion_from_audio({
            "rms": features["energy"],
            "zcr": features["pitch_variation"] / 100.0,
            "centroid": features["speech_rate"] * 10.0
        })
        vocal_emotion = acoustic_analysis.get("emotion", "neutral")

        # 5. Gemini AI Emotional Response (strictly based on TEXT content, behaving exactly like text mode)
        gemini_output = get_emotional_response(
            user_message=masked_text,
            input_type="text",
            audio_features=None
        )

        if not gemini_output:
            gemini_output = {
                "emotion": "neutral",
                "stress_score": 20,
                "analysis": "Failed to fully analyze audio.",
                "ai_response": "I heard you, but I'm having trouble analyzing the emotion. Could you try telling me again?",
                "wellness_tip": "Take a deep breath."
            }

        # 5. Build JSON Payload
        stress_score = gemini_output.get("stress_score", 0)
        final_payload = {
            "transcription": transcription,
            "masked_text": masked_text,
            "emotion": vocal_emotion,
            "stress_score": stress_score,
            "stress_level": "high" if stress_score > 60 else "medium" if stress_score > 40 else "low",
            "analysis": gemini_output.get("analysis", ""),
            "ai_response": gemini_output.get("ai_response", ""),
            "wellness_tip": gemini_output.get("wellness_tip", ""),
            "audio_features": features
        }

        # 6. Save to Firestore (History)
        if db:
            db.collection("chats").add({
                "user_id": user_id,
                "session_id": "voice_session",
                "user_message": masked_text,
                "ai_response": final_payload["ai_response"],
                "emotion": final_payload["emotion"],
                "score": final_payload["stress_score"],
                "stress_level": final_payload["stress_level"],
                "analysis": final_payload["analysis"],
                "emergency": stress_score >= 80,
                "is_private": False,
                "input_type": "voice",
                "created_at": datetime.datetime.utcnow()
            })

        if os.path.exists(file_path):
            os.remove(file_path)

        return JSONResponse(content=final_payload)

    except Exception as e:
        print("AUDIO ROUTE ERROR:", e)
        if file_path and os.path.exists(file_path):
            os.remove(file_path)

        return JSONResponse(status_code=500, content={
            "error": str(e),
            "message": "Audio processing failed"
        })
