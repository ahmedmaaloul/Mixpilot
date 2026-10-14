"""German for Mixpilot. The source of truth for the String Catalogs: edit here, then run
`python3 Localization/localize.py`.

Use Apple's own German terms: Einstellungen, Ausgabegerät, Ton aus, Lautstärke, Mikrofon,
Eingangslautstärke, Beenden. Informal "du", „…“ quotes, a space before an ellipsis ("Einstellungen …").
"""

# English key (exactly as in the code) → German.
DE = {
    # Call mode ("Anrufmodus", masculine) and microphone.
    "Call Mode": "Anrufmodus",
    "In Call": "Im Anruf",
    "In use by %@.": "Verwendet von %@.",
    "Input Volume": "Eingangslautstärke",
    "Lowered": "Leiser",
    "Lowers other apps when a call starts.": "Macht andere Apps leiser, wenn ein Anruf beginnt.",
    "Microphone": "Mikrofon",
    "Mixpilot, Call Mode On": "Mixpilot, Anrufmodus ein",
    "Mixpilot, Microphone Off": "Mixpilot, Mikrofon aus",
    "No Microphone": "Kein Mikrofon",
    "Off for all apps.": "Für alle Apps aus.",
    "On during your call in %@.": "Ein während deines Anrufs in %@.",
    "On until you turn it off.": "Ein, bis du ihn ausschaltest.",
    "%@ (Not Connected)": "%@ (nicht verbunden)",
    "About Mixpilot": "Über Mixpilot",
    "Apps appear here when they play sound.": "Apps werden hier angezeigt, wenn sie Ton wiedergeben.",
    "More": "Mehr",
    "Mute": "Ton aus",
    "Open System Settings": "Systemeinstellungen öffnen",
    "Output": "Ausgabe",
    "Output: %@": "Ausgabe: %@",
    "To change the volume of apps, allow Mixpilot to record system audio.":
        "Erlaube Mixpilot die Systemaudioaufnahme, damit du die Lautstärke von Apps ändern kannst.",
    "Unmute": "Ton ein",
    "Use System Setting": "Systemeinstellung verwenden",
    "Volume": "Lautstärke",
    "No Apps Playing Sound": "Keine App gibt Ton wieder",
    "Quit Mixpilot": "Mixpilot beenden",
    "Unknown App": "Unbekannte App",
}

# Info.plist key → (English, German).
INFOPLIST = {
    "NSAudioCaptureUsageDescription": (
        "Mixpilot needs access to the sound apps play so you can change each app’s volume. "
        "Sound is processed on your Mac and is never saved or sent.",
        "Mixpilot benötigt Zugriff auf den Ton von Apps, damit du die Lautstärke jeder App ändern kannst. "
        "Der Ton wird auf deinem Mac verarbeitet und weder gespeichert noch gesendet.",
    ),
}
