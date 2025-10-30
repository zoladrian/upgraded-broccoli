package com.example.speechbridge;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public class SpeechBridge extends GodotPlugin implements RecognitionListener, TextToSpeech.OnInitListener {
    private static final int REQUEST_RECORD_AUDIO = 1001;
    private SpeechRecognizer speechRecognizer;
    private TextToSpeech textToSpeech;
    private Intent recognizerIntent;
    private final Godot godot;

    public SpeechBridge(Godot godot) {
        super(godot);
        this.godot = godot;
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "SpeechBridge";
    }

    @NonNull
    @Override
    public List<String> getPluginMethods() {
        return Arrays.asList("startListening", "stopListening", "speak");
    }

    @Override
    public List<SignalInfo> getPluginSignals() {
        return Arrays.asList(
                new SignalInfo("onSpeechEvent", Object.class)
        );
    }

    @Override
    public void onMainCreate(Bundle bundle) {
        requestPermission();
        textToSpeech = new TextToSpeech(godot.getApplicationContext(), this);
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(godot.getApplicationContext());
        speechRecognizer.setRecognitionListener(this);
        recognizerIntent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault());
    }

    public void startListening() {
        Activity activity = getActivity();
        if (activity == null) return;
        requestPermission();
        speechRecognizer.startListening(recognizerIntent);
        emitSignal("onSpeechEvent", buildPayload("listening", true));
    }

    public void stopListening() {
        if (speechRecognizer != null) {
            speechRecognizer.stopListening();
        }
        emitSignal("onSpeechEvent", buildPayload("listening", false));
    }

    public void speak(String text) {
        if (textToSpeech != null) {
            textToSpeech.speak(text, TextToSpeech.QUEUE_FLUSH, null, "SpeechBridgeUtterance");
        }
    }

    private void requestPermission() {
        Activity activity = getActivity();
        if (activity == null) return;
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(activity, new String[]{Manifest.permission.RECORD_AUDIO}, REQUEST_RECORD_AUDIO);
        }
    }

    @Override
    public void onResults(Bundle bundle) {
        List<String> results = bundle.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        if (results != null && !results.isEmpty()) {
            emitSignal("onSpeechEvent", buildPayload("transcription", results.get(0)));
        }
    }

    @Override
    public void onError(int error) {
        emitSignal("onSpeechEvent", buildErrorPayload(String.valueOf(error)));
    }

    @Override
    public void onInit(int status) {
        if (status == TextToSpeech.SUCCESS) {
            textToSpeech.setLanguage(Locale.getDefault());
        }
    }

    @Override
    public void onBeginningOfSpeech() { }

    @Override
    public void onBufferReceived(byte[] buffer) { }

    @Override
    public void onEndOfSpeech() { }

    @Override
    public void onEvent(int eventType, Bundle params) { }

    @Override
    public void onPartialResults(Bundle partialResults) { }

    @Override
    public void onReadyForSpeech(Bundle params) { }

    @Override
    public void onRmsChanged(float rmsdB) { }

    private String buildPayload(String type, Object value) {
        JSONObject json = new JSONObject();
        try {
            json.put("type", type);
            if ("listening".equals(type)) {
                json.put("active", value);
            } else if ("transcription".equals(type)) {
                json.put("text", value);
            }
        } catch (JSONException ignored) { }
        return json.toString();
    }

    private String buildErrorPayload(String message) {
        JSONObject json = new JSONObject();
        try {
            json.put("type", "error");
            json.put("message", message);
        } catch (JSONException ignored) { }
        return json.toString();
    }
}
