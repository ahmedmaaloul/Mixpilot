"""Builds mixpilot.blitzraum.com into website/public: static HTML in English and German, no
JavaScript, no cookies, no trackers.

    python3 website/build.py

Edit the texts below (both languages), then run it and commit website/public. The download
(public/download/Mixpilot.dmg) is copied there by scripts/release-mac.sh.
"""
import html
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent
PUBLIC = ROOT / "public"
SITE = "https://mixpilot.blitzraum.com"
EMAIL = "support@blitzraum.com"
VERSION = "0.1"
YEAR = "2026"

TEXT = {
    "en": {
        "title": "Mixpilot – The volume of every app on your Mac",
        "description": "Mixpilot puts a volume slider for each app in your Mac’s menu bar, lowers other apps during calls and shows who uses your microphone. Free for macOS.",
        "nav_features": "Features",
        "nav_privacy": "Privacy",
        "nav_support": "Support",
        "download": "Download",
        "download_mac": "Download for Mac",
        "requirements": f"Version {VERSION} · macOS 14.4 or later · Free",
        "install_hint": "Open the disk image and drag Mixpilot into the Applications folder.",
        "hero_title": "Every app.<br>Its own volume.",
        "hero_text": "Mixpilot puts a volume slider for each app in your menu bar, and turns everything else down when a call starts.",
        "panel_call_alt": "The Mixpilot panel during a FaceTime call: Call Mode is on, FaceTime plays at full volume, Music, Podcasts and Safari are lowered, and FaceTime is using the microphone.",
        "panel_apps_alt": "The Mixpilot panel with FaceTime, Music, Podcasts and Safari, each with its own volume slider, mute button and output device.",
        "apps_eyebrow": "Volume for each app",
        "apps_title": "Turn down what you don’t need.<br>Hear what you do.",
        "apps_text": "Every app that plays sound gets its own slider and mute button, right in the menu bar. Music softer, the video louder, notifications quiet. Mixpilot remembers each app and sets it again the next time it plays.",
        "calls_eyebrow": "Call Mode",
        "calls_title": "Calls come first.",
        "calls_text": "When a call starts in WhatsApp, FaceTime, Zoom, Teams, Webex, Discord or a browser tab, every other app fades down, and comes back when you hang up. You choose how quiet. Your own volumes never change.",
        "tiles": [
            ("output", "Any output for any app.", "Your call in your AirPods, the music on the speakers. When a device disconnects, the app follows your Mac, and goes back when it reconnects."),
            ("mic", "Your microphone at a glance.", "See which apps use it, set its input volume, and turn it off for every app at once. The menu bar shows when it’s off."),
            ("keyboard", "Keyboard shortcuts.", "Turn the microphone or call mode on or off, and the app in front up or down, from anywhere."),
            ("shield", "Never louder than the app.", "Mixpilot only turns apps down, never up past their own level, to protect your hearing and your speakers."),
            ("mac", "Made for macOS.", "Native controls and Liquid Glass, light and dark, VoiceOver and keyboard navigation, in English and German."),
            ("restore", "Nothing goes silent.", "If Mixpilot quits or crashes, every app plays normally again, and a microphone it turned off comes back on."),
        ],
        "privacy_eyebrow": "Privacy",
        "privacy_title": "Sound stays on your Mac.",
        "privacy_text": "Mixpilot changes sound on your Mac, as it plays. It never records, saves or sends it. No accounts, no analytics, no network access.",
        "privacy_link": "Read the privacy policy",
        "cta_title": "Free. For your Mac.",
        "cta_text": "Requires macOS 14.4 or later. Signed with a Developer ID and notarized by Apple.",
        "footer_license": f"Mixpilot is free for personal and other noncommercial use. For commercial use, ask at {EMAIL}.",
        "footer_trademarks": "Apple, Mac, macOS, FaceTime and AirPods are trademarks of Apple Inc. Other product names are trademarks of their owners. Mixpilot is not affiliated with Apple.",
        "other_language": "Deutsch",
        "skip": "Skip to content",
        # Privacy policy
        "privacy_page_title": "Privacy Policy – Mixpilot",
        "privacy_heading": "Privacy Policy",
        "privacy_updated": "Last updated: October 14, 2026",
        "privacy_sections": [
            ("The app", [
                "Mixpilot doesn’t collect, store or send any personal data. It has no accounts, no analytics, no advertising and no network access.",
                "To change an app’s volume, Mixpilot needs macOS’s <b>System Audio Recording</b> permission. It receives the sound apps play and plays it again at the volume you choose, on your Mac, in real time. Sound is never recorded, saved or sent.",
                "Mixpilot sees which apps use the microphone, and can turn the microphone off for all apps and set its input volume. It never receives or records what the microphone hears.",
                "Your settings (volumes, output devices, call mode, keyboard shortcuts) are stored on your Mac, in Mixpilot’s preferences. Deleting the app and its preferences removes them.",
            ]),
            ("This website", [
                "This website uses no cookies, no analytics and no third-party content. It is hosted by Vercel Inc. (USA), which processes technical data such as your IP address and the pages requested in its server logs to deliver the site and keep it secure. See Vercel’s privacy policy at vercel.com/legal/privacy-policy.",
            ]),
            ("Contact", [
                f"Ahmed Maaloul, the developer of Mixpilot, is responsible for this app and website. Questions about privacy: <a href=\"mailto:{EMAIL}\">{EMAIL}</a>. Under the GDPR you have the right to access, correct and delete your data and to lodge a complaint with a supervisory authority.",
            ]),
        ],
        # Support
        "support_page_title": "Support – Mixpilot",
        "support_heading": "Support",
        "support_intro": f"Answers to common questions. Something else? Write to <a href=\"mailto:{EMAIL}\">{EMAIL}</a>.",
        "faq": [
            ("Mixpilot doesn’t change an app’s volume.",
             "Mixpilot needs the System Audio Recording permission. Open System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, and turn on Mixpilot under “System Audio Recording Only”."),
            ("Other apps are too quiet, or too loud, during calls.",
             "Open Mixpilot’s Settings ▸ Calls and set “Volume of Other Apps”. You can also choose which apps start call mode, or turn it on and off yourself in the menu bar."),
            ("The menu bar icon is gone.",
             "Open Mixpilot again from the Applications folder or Spotlight: its Settings appear. Turn on “Show in Menu Bar”. On a crowded menu bar, macOS may also move it behind the arrow next to the other icons."),
            ("Does Mixpilot record my calls?",
             "No. Mixpilot never records, saves or sends sound, and it never hears your microphone."),
            ("Can Mixpilot make an app louder than it is?",
             "No, on purpose. Mixpilot only turns apps down, to protect your hearing and your speakers."),
            ("How do I uninstall Mixpilot?",
             "Quit Mixpilot from its menu (⋯ ▸ Quit Mixpilot) and move it to the Trash. Every app plays normally again."),
        ],
        # 404
        "notfound_title": "Page Not Found – Mixpilot",
        "notfound_heading": "This page can’t be found.",
        "notfound_link": "Go to Mixpilot’s home page",
    },
    "de": {
        "title": "Mixpilot – Die Lautstärke jeder App auf deinem Mac",
        "description": "Mixpilot gibt jeder App einen eigenen Lautstärkeregler in der Menüleiste deines Mac, macht andere Apps bei Anrufen leiser und zeigt, wer dein Mikrofon verwendet. Kostenlos für macOS.",
        "nav_features": "Funktionen",
        "nav_privacy": "Datenschutz",
        "nav_support": "Support",
        "download": "Laden",
        "download_mac": "Für Mac laden",
        "requirements": f"Version {VERSION} · macOS 14.4 oder neuer · Kostenlos",
        "install_hint": "Öffne das Disk-Image und zieh Mixpilot in den Ordner „Programme“.",
        "hero_title": "Jede App.<br>Ihre eigene Lautstärke.",
        "hero_text": "Mixpilot gibt jeder App einen eigenen Lautstärkeregler in der Menüleiste und macht alles andere leiser, sobald ein Anruf beginnt.",
        "panel_call_alt": "Das Mixpilot-Fenster während eines FaceTime-Anrufs: Der Anrufmodus ist ein, FaceTime spielt mit voller Lautstärke, Musik, Podcasts und Safari sind leiser, und FaceTime verwendet das Mikrofon.",
        "panel_apps_alt": "Das Mixpilot-Fenster mit FaceTime, Musik, Podcasts und Safari, jeweils mit eigenem Lautstärkeregler, Taste für „Ton aus“ und Ausgabegerät.",
        "apps_eyebrow": "Lautstärke für jede App",
        "apps_title": "Leiser, was du nicht brauchst.<br>Hören, was zählt.",
        "apps_text": "Jede App, die Ton wiedergibt, bekommt ihren eigenen Regler und eine Taste für „Ton aus“ – direkt in der Menüleiste. Musik leiser, das Video lauter, Mitteilungen ruhig. Mixpilot merkt sich jede App und stellt sie wieder ein, sobald sie das nächste Mal spielt.",
        "calls_eyebrow": "Anrufmodus",
        "calls_title": "Anrufe haben Vorrang.",
        "calls_text": "Beginnt ein Anruf in WhatsApp, FaceTime, Zoom, Teams, Webex, Discord oder einem Browser-Tab, werden alle anderen Apps sanft leiser – und nach dem Auflegen wieder lauter. Du bestimmst, wie leise. Deine eigenen Einstellungen bleiben unverändert.",
        "tiles": [
            ("output", "Jede Ausgabe für jede App.", "Dein Anruf in den AirPods, die Musik über die Lautsprecher. Wird ein Gerät getrennt, folgt die App deinem Mac – und wechselt zurück, sobald es wieder verbunden ist."),
            ("mic", "Dein Mikrofon auf einen Blick.", "Sieh, welche Apps es verwenden, stell die Eingangslautstärke ein und schalte es für alle Apps auf einmal aus. Die Menüleiste zeigt, wenn es aus ist."),
            ("keyboard", "Tastaturkurzbefehle.", "Schalte Mikrofon oder Anrufmodus ein und aus und mach die App im Vordergrund lauter oder leiser – von überall."),
            ("shield", "Nie lauter als die App.", "Mixpilot macht Apps nur leiser, nie lauter als ihre eigene Lautstärke – zum Schutz deines Gehörs und deiner Lautsprecher."),
            ("mac", "Gemacht für macOS.", "Native Bedienelemente und Liquid Glass, hell und dunkel, VoiceOver und Tastaturbedienung, auf Deutsch und Englisch."),
            ("restore", "Nichts wird stumm.", "Wird Mixpilot beendet oder stürzt ab, spielen alle Apps wieder normal, und ein ausgeschaltetes Mikrofon ist wieder an."),
        ],
        "privacy_eyebrow": "Datenschutz",
        "privacy_title": "Der Ton bleibt auf deinem Mac.",
        "privacy_text": "Mixpilot verändert den Ton auf deinem Mac, während er spielt. Er wird nie aufgenommen, gespeichert oder gesendet. Keine Accounts, keine Analysen, kein Netzwerkzugriff.",
        "privacy_link": "Datenschutzerklärung lesen",
        "cta_title": "Kostenlos. Für deinen Mac.",
        "cta_text": "Erfordert macOS 14.4 oder neuer. Mit einer Developer ID signiert und von Apple beglaubigt.",
        "footer_license": f"Mixpilot ist für private und andere nicht kommerzielle Nutzung kostenlos. Für kommerzielle Nutzung frag bitte unter {EMAIL}.",
        "footer_trademarks": "Apple, Mac, macOS, FaceTime und AirPods sind Marken der Apple Inc. Andere Produktnamen sind Marken ihrer Inhaber. Mixpilot steht in keiner Verbindung zu Apple.",
        "other_language": "English",
        "skip": "Zum Inhalt springen",
        "privacy_page_title": "Datenschutzerklärung – Mixpilot",
        "privacy_heading": "Datenschutzerklärung",
        "privacy_updated": "Stand: 14. Oktober 2026",
        "privacy_sections": [
            ("Die App", [
                "Mixpilot erhebt, speichert und sendet keine personenbezogenen Daten. Es gibt keine Accounts, keine Analysen, keine Werbung und keinen Netzwerkzugriff.",
                "Um die Lautstärke einer App zu ändern, braucht Mixpilot die macOS-Berechtigung <b>Systemaudioaufnahme</b>. Mixpilot erhält den Ton, den Apps wiedergeben, und spielt ihn in der von dir gewählten Lautstärke wieder ab – auf deinem Mac, in Echtzeit. Der Ton wird nie aufgenommen, gespeichert oder gesendet.",
                "Mixpilot sieht, welche Apps das Mikrofon verwenden, und kann das Mikrofon für alle Apps ausschalten und seine Eingangslautstärke einstellen. Was das Mikrofon hört, erhält oder speichert Mixpilot nie.",
                "Deine Einstellungen (Lautstärken, Ausgabegeräte, Anrufmodus, Tastaturkurzbefehle) werden auf deinem Mac in den Einstellungen von Mixpilot gespeichert. Löschst du die App und ihre Einstellungen, sind sie entfernt.",
            ]),
            ("Diese Website", [
                "Diese Website verwendet keine Cookies, keine Analysen und keine Inhalte Dritter. Sie wird von Vercel Inc. (USA) gehostet, die technische Daten wie deine IP-Adresse und die abgerufenen Seiten in Server-Logs verarbeitet, um die Website auszuliefern und zu schützen. Siehe die Datenschutzerklärung von Vercel unter vercel.com/legal/privacy-policy.",
            ]),
            ("Kontakt", [
                f"Verantwortlich für App und Website ist Ahmed Maaloul, der Entwickler von Mixpilot. Fragen zum Datenschutz: <a href=\"mailto:{EMAIL}\">{EMAIL}</a>. Nach der DSGVO hast du das Recht auf Auskunft, Berichtigung und Löschung deiner Daten und auf Beschwerde bei einer Aufsichtsbehörde.",
            ]),
        ],
        "support_page_title": "Support – Mixpilot",
        "support_heading": "Support",
        "support_intro": f"Antworten auf häufige Fragen. Etwas anderes? Schreib an <a href=\"mailto:{EMAIL}\">{EMAIL}</a>.",
        "faq": [
            ("Mixpilot ändert die Lautstärke einer App nicht.",
             "Mixpilot braucht die Berechtigung „Systemaudioaufnahme“. Öffne Systemeinstellungen ▸ Datenschutz & Sicherheit ▸ Bildschirm- & Systemaudioaufnahme und aktiviere Mixpilot unter „Nur Systemaudioaufnahme“."),
            ("Andere Apps sind bei Anrufen zu leise oder zu laut.",
             "Öffne in Mixpilot Einstellungen ▸ Anrufe und stell „Lautstärke anderer Apps“ ein. Dort wählst du auch, welche Apps den Anrufmodus starten. In der Menüleiste kannst du ihn jederzeit selbst ein- und ausschalten."),
            ("Das Symbol in der Menüleiste ist weg.",
             "Öffne Mixpilot erneut aus dem Ordner „Programme“ oder über Spotlight: Die Einstellungen erscheinen. Aktiviere „In der Menüleiste anzeigen“. Ist die Menüleiste voll, legt macOS Symbole auch hinter den Pfeil neben den anderen Symbolen."),
            ("Nimmt Mixpilot meine Anrufe auf?",
             "Nein. Mixpilot nimmt nie Ton auf, speichert oder sendet ihn nicht und hört dein Mikrofon nie."),
            ("Kann Mixpilot eine App lauter machen, als sie ist?",
             "Nein, mit Absicht. Mixpilot macht Apps nur leiser – zum Schutz deines Gehörs und deiner Lautsprecher."),
            ("Wie deinstalliere ich Mixpilot?",
             "Beende Mixpilot über sein Menü (⋯ ▸ Mixpilot beenden) und bewege es in den Papierkorb. Alle Apps spielen wieder normal."),
        ],
        "notfound_title": "Seite nicht gefunden – Mixpilot",
        "notfound_heading": "Diese Seite gibt es nicht.",
        "notfound_link": "Zur Startseite von Mixpilot",
    },
}

# Simple line icons in the style of the site (24×24, 1.6 stroke, currentColor).
ICONS = {
    "output": '<path d="M4 13v-1a8 8 0 0 1 16 0v1"/><rect x="3" y="13" width="4" height="7" rx="1.5"/><rect x="17" y="13" width="4" height="7" rx="1.5"/>',
    "mic": '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
    "keyboard": '<rect x="2.5" y="6" width="19" height="12" rx="2.5"/><path d="M6 10h.01M9 10h.01M12 10h.01M15 10h.01M18 10h.01M7 14h10"/>',
    "shield": '<path d="M12 3 5 6v5c0 4.5 3 8.3 7 10 4-1.7 7-5.5 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-4"/>',
    "mac": '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
    "restore": '<path d="M4 12a8 8 0 1 0 2.4-5.7"/><path d="M4 4v5h5"/>',
}


def path_for(lang, page):
    """Paths without trailing slashes (vercel.json: trailingSlash false), so no redirects."""
    if page == "index":
        return "/" if lang == "en" else "/de"
    return f"/{page}" if lang == "en" else f"/de/{page}"


def head(lang, t, title, description, page):
    other = "de" if lang == "en" else "en"
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{html.escape(description)}">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#fbfbfd" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
<link rel="canonical" href="{SITE}{path_for(lang, page)}">
<link rel="alternate" hreflang="{lang}" href="{SITE}{path_for(lang, page)}">
<link rel="alternate" hreflang="{other}" href="{SITE}{path_for(other, page)}">
<link rel="alternate" hreflang="x-default" href="{SITE}{path_for("en", page)}">
<link rel="icon" type="image/png" href="/assets/favicon.png">
<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
<link rel="stylesheet" href="/assets/style.css">
<meta property="og:type" content="website">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{html.escape(description)}">
<meta property="og:url" content="{SITE}{path_for(lang, page)}">
<meta property="og:image" content="{SITE}/assets/og.png">
<meta name="twitter:card" content="summary_large_image">
</head>
<body>
<a class="skip" href="#main">{t["skip"]}</a>
"""


def nav(lang, t):
    home = path_for(lang, "index")
    return f"""<header class="nav">
  <nav aria-label="Mixpilot">
    <a class="brand" href="{home}"><img src="/assets/icon-64.png" width="22" height="22" alt="">Mixpilot</a>
    <ul>
      <li><a href="{home}#features">{t["nav_features"]}</a></li>
      <li><a href="{path_for(lang, "privacy")}">{t["nav_privacy"]}</a></li>
      <li><a href="{path_for(lang, "support")}">{t["nav_support"]}</a></li>
    </ul>
    <a class="pill small" href="/download/Mixpilot.dmg">{t["download"]}</a>
  </nav>
</header>
"""


def footer(lang, t, page):
    other = "de" if lang == "en" else "en"
    return f"""<footer class="footer">
  <div class="wrap">
    <p>{html.escape(t["footer_license"])}</p>
    <p>{html.escape(t["footer_trademarks"])}</p>
    <div class="footer-row">
      <span>© {YEAR} Ahmed Maaloul</span>
      <span class="links">
        <a href="{path_for(lang, "privacy")}">{t["nav_privacy"]}</a>
        <a href="{path_for(lang, "support")}">{t["nav_support"]}</a>
        <a href="{path_for(other, page)}" hreflang="{other}" lang="{other}">{t["other_language"]}</a>
      </span>
    </div>
  </div>
</footer>
</body>
</html>
"""


def screenshot(name, lang, alt):
    return f"""<picture>
        <source media="(prefers-color-scheme: dark)" srcset="/assets/{name}-{lang}-dark.png">
        <img class="panel" src="/assets/{name}-{lang}-light.png" width="320" height="403" alt="{html.escape(alt)}">
      </picture>"""


def index(lang):
    t = TEXT[lang]
    tiles = "\n".join(
        f"""      <article class="tile">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true">{ICONS[icon]}</svg>
        <h3>{html.escape(title)}</h3>
        <p>{html.escape(text)}</p>
      </article>"""
        for icon, title, text in t["tiles"]
    )
    return head(lang, t, t["title"], t["description"], "index") + nav(lang, t) + f"""<main id="main">
  <section class="hero">
    <div class="wrap">
      <img class="app-icon" src="/assets/icon-256.png" width="128" height="128" alt="">
      <h1>{t["hero_title"]}</h1>
      <p class="lead">{html.escape(t["hero_text"])}</p>
      <p><a class="pill" href="/download/Mixpilot.dmg">{t["download_mac"]}</a></p>
      <p class="fine">{t["requirements"]}<br>{html.escape(t["install_hint"])}</p>
    </div>
    <div class="stage">
      {screenshot("panel-call", lang, t["panel_call_alt"])}
    </div>
  </section>

  <section class="feature" id="features">
    <div class="wrap split">
      <div class="copy">
        <p class="eyebrow">{t["apps_eyebrow"]}</p>
        <h2>{t["apps_title"]}</h2>
        <p>{html.escape(t["apps_text"])}</p>
      </div>
      <div class="stage small">
        {screenshot("panel-apps", lang, t["panel_apps_alt"])}
      </div>
    </div>
  </section>

  <section class="feature alt">
    <div class="wrap narrow">
      <p class="eyebrow">{t["calls_eyebrow"]}</p>
      <h2>{t["calls_title"]}</h2>
      <p>{html.escape(t["calls_text"])}</p>
    </div>
  </section>

  <section class="feature">
    <div class="wrap grid">
{tiles}
    </div>
  </section>

  <section class="feature alt">
    <div class="wrap narrow">
      <p class="eyebrow">{t["privacy_eyebrow"]}</p>
      <h2>{t["privacy_title"]}</h2>
      <p>{html.escape(t["privacy_text"])}</p>
      <p><a class="more" href="{path_for(lang, "privacy")}">{t["privacy_link"]}</a></p>
    </div>
  </section>

  <section class="cta">
    <div class="wrap narrow">
      <img class="app-icon" src="/assets/icon-256.png" width="96" height="96" alt="">
      <h2>{t["cta_title"]}</h2>
      <p><a class="pill" href="/download/Mixpilot.dmg">{t["download_mac"]}</a></p>
      <p class="fine">{html.escape(t["install_hint"])}<br>{html.escape(t["cta_text"])}</p>
    </div>
  </section>
</main>
""" + footer(lang, t, "index")


def privacy(lang):
    t = TEXT[lang]
    sections = "\n".join(
        f"    <h2>{html.escape(title)}</h2>\n" + "\n".join(f"    <p>{p}</p>" for p in paragraphs)
        for title, paragraphs in t["privacy_sections"]
    )
    return head(lang, t, t["privacy_page_title"], t["description"], "privacy") + nav(lang, t) + f"""<main id="main" class="document">
  <div class="wrap narrow">
    <h1>{t["privacy_heading"]}</h1>
    <p class="fine">{t["privacy_updated"]}</p>
{sections}
  </div>
</main>
""" + footer(lang, t, "privacy")


def support(lang):
    t = TEXT[lang]
    faq = "\n".join(
        f"    <details>\n      <summary>{html.escape(q)}</summary>\n      <p>{html.escape(a)}</p>\n    </details>"
        for q, a in t["faq"]
    )
    return head(lang, t, t["support_page_title"], t["description"], "support") + nav(lang, t) + f"""<main id="main" class="document">
  <div class="wrap narrow">
    <h1>{t["support_heading"]}</h1>
    <p>{t["support_intro"]}</p>
{faq}
  </div>
</main>
""" + footer(lang, t, "support")


def not_found():
    t = TEXT["en"]
    return head("en", t, t["notfound_title"], t["description"], "index") + nav("en", t) + f"""<main id="main" class="document center">
  <div class="wrap narrow">
    <h1>{t["notfound_heading"]}</h1>
    <p><a class="more" href="/">{t["notfound_link"]}</a></p>
  </div>
</main>
""" + footer("en", t, "index")


def main():
    # Keep the published download across rebuilds.
    download = PUBLIC / "download"
    saved = download.exists()
    if saved:
        shutil.move(download, ROOT / ".download-keep")
    if PUBLIC.exists():
        shutil.rmtree(PUBLIC)
    (PUBLIC / "de").mkdir(parents=True)
    if saved:
        shutil.move(ROOT / ".download-keep", download)
    shutil.copytree(ROOT / "assets", PUBLIC / "assets")

    pages = {"index": index, "privacy": privacy, "support": support}
    for lang in ("en", "de"):
        base = PUBLIC if lang == "en" else PUBLIC / "de"
        for name, render in pages.items():
            (base / f"{name}.html").write_text(render(lang))
    (PUBLIC / "404.html").write_text(not_found())

    urls = [f"{SITE}{path_for(lang, page)}" for lang in ("en", "de") for page in pages]
    (PUBLIC / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"  <url><loc>{url}</loc></url>\n" for url in urls)
        + "</urlset>\n"
    )
    (PUBLIC / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {SITE}/sitemap.xml\n")
    print(f"Built {len(urls) + 1} pages into {PUBLIC}")


main()
