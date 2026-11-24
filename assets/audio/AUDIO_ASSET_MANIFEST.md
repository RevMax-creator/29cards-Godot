# 29 Cards — Audio Asset Manifest & Licensing Specification

## Runtime Directory Layout
```text
assets/
└── audio/
    ├── music/
    │   └── background_music.ogg
    ├── voice/
    │   ├── pass.ogg
    │   ├── bid_15.ogg
    │   └── ... (through bid_28.ogg)
    ├── sfx/
    │   ├── shuffle.ogg
    │   ├── card_deal.ogg
    │   ├── card_sort.ogg
    │   ├── card_place.ogg
    │   ├── trick_collect.ogg
    │   ├── ui_click.ogg
    │   ├── turn_alert.ogg
    │   ├── trump_select.ogg
    │   ├── trump_reveal.ogg
    │   ├── bid_pass.ogg
    │   ├── double.ogg
    │   ├── redouble.ogg
    │   ├── pair_declared.ogg
    │   ├── hand_win.ogg
    │   ├── hand_loss.ogg
    │   ├── match_win.ogg
    │   ├── match_loss.ogg
    │   └── error.ogg
    └── AUDIO_ASSET_MANIFEST.md
```

---

## 1. Background Music (Preserved)
- **File**: `assets/audio/music/background_music.ogg` (48.000s, 44,100 Hz Stereo Ogg Vorbis, Peak `-7.6 dBFS`, RMS `-18.4 dBFS`)
- **Status**: Preserved bit-for-bit from original `assets/audio/card_table_ambient.ogg`. Playback level configured at `-14.5 dB` on `Music` bus.
- **License**: In-project original ambient loop (`tools/`), cleared for commercial distribution inside 29 Cards.

---

## 2. Spoken Auction Voice Announcements (Preserved)
- **Files**: `assets/audio/voice/bid_15.ogg` .. `bid_28.ogg` and `pass.ogg` (48,000 Hz Stereo Ogg Vorbis, -16 LUFS RMS target, -1.5 dBFS max peak)
- **Status**: Preserved bit-for-bit; no pitch/rate changes.
- **Engine**: Edge Neural Speech Synthesis (`en-US-ChristopherNeural`) — original synthetic AI voice persona.
- **License**: Microsoft Cognitive Services Neural Voice — commercial use and compiled game distribution permitted.

| Key | File | Announcement Phrase | Duration | Peak | RMS |
|---|---|---|---|---|---|
| `pass` | `voice/pass.ogg` | "Pass." | 0.674s | 0.826 | 0.091 |
| `bid_15` | `voice/bid_15.ogg` | "Fifteen." | 0.718s | 0.825 | 0.123 |
| `bid_16` | `voice/bid_16.ogg` | "Sixteen." | 0.878s | 0.814 | 0.130 |
| `bid_17` | `voice/bid_17.ogg` | "Seventeen." | 0.945s | 0.825 | 0.118 |
| `bid_18` | `voice/bid_18.ogg` | "Eighteen." | 0.661s | 0.765 | 0.140 |
| `bid_19` | `voice/bid_19.ogg` | "Nineteen." | 0.772s | 0.857 | 0.130 |
| `bid_20` | `voice/bid_20.ogg` | "Twenty." | 0.580s | 0.842 | 0.107 |
| `bid_21` | `voice/bid_21.ogg` | "Twenty-one." | 0.707s | 0.842 | 0.136 |
| `bid_22` | `voice/bid_22.ogg` | "Twenty-two." | 0.772s | 0.848 | 0.133 |
| `bid_23` | `voice/bid_23.ogg` | "Twenty-three." | 0.737s | 0.826 | 0.130 |
| `bid_24` | `voice/bid_24.ogg` | "Twenty-four." | 0.731s | 0.822 | 0.130 |
| `bid_25` | `voice/bid_25.ogg` | "Twenty-five." | 0.920s | 0.825 | 0.123 |
| `bid_26` | `voice/bid_26.ogg` | "Twenty-six." | 0.949s | 0.842 | 0.119 |
| `bid_27` | `voice/bid_27.ogg` | "Twenty-seven." | 0.825s | 0.824 | 0.122 |
| `bid_28` | `voice/bid_28.ogg` | "Twenty-eight." | 0.734s | 0.847 | 0.134 |

---

## 3. Gameplay & Table SFX Inventory and Licensing

All processed SFX run at **48,000 Hz Stereo Ogg Vorbis** with DC-removal, high-pass filtering (90–100 Hz) to strip handling rumble, smooth fade-in/out envelopes, and zero clipping.

| Runtime File | Original Filename & Source Pack | Creator | Exact License & URL | Commercial / Modify / Redistribute in Game | Attribution Required | Processing Applied | Runtime Specs |
|---|---|---|---|---|---|---|---|
| `sfx/shuffle.ogg` | `kenney_casino-audio/Audio/card-shuffle.ogg` | Kenney Vleugels | CC0 1.0 Universal | Yes / Yes / Yes | Resampled to 48kHz stereo, trimmed 100ms..2940ms, sped up 1.3x, 15ms/45ms fades, soft-compressed | Replaced previous deck shuffle with 1.3x-quickened Kenney card-shuffle | 2.185s, 48kHz, RMS -19.5dB, Peak -1.3dB |
| `sfx/card_slide_1..8.ogg` | `kenney_casino-audio/Audio/card-slide-1..8.ogg` ([Kenney Casino Audio v1.1](https://kenney.nl/assets/casino-audio)) | Kenney Vleugels (`kenney.nl`) | **CC0 1.0 Universal** ([creativecommons.org/publicdomain/zero/1.0/](http://creativecommons.org/publicdomain/zero/1.0/)) | Yes / Yes / Yes | No (optional) | 90 Hz HPF, active burst trimmed, 3–4ms/25–30ms fades, normalized, 48kHz (randomized 1..8 on deal) | 0.086–0.258s, 48kHz, RMS -21.5 to -22.9dB |
| `sfx/card_sort.ogg` | `kenney_casino-audio/Audio/card-fan-1.ogg` ([Kenney Casino Audio v1.1](https://kenney.nl/assets/casino-audio)) | Kenney Vleugels (`kenney.nl`) | **CC0 1.0 Universal** ([creativecommons.org/publicdomain/zero/1.0/](http://creativecommons.org/publicdomain/zero/1.0/)) | Yes / Yes / Yes | No (optional) | 100 Hz HPF + 5.5 kHz LPF, trimmed 260–600ms, 10ms/45ms fades, 48kHz | 0.340s, 48kHz, RMS -20.0dB, Peak -4.2dB |
| `sfx/card_place.ogg`, `sfx/card_place_2..4.ogg` | `kenney_casino-audio/Audio/card-place-1..4.ogg` + `card-slide-1..8.ogg` ([Kenney Casino Audio v1.1](https://kenney.nl/assets/casino-audio)) | Kenney Vleugels (`kenney.nl`) | **CC0 1.0 Universal** ([creativecommons.org/publicdomain/zero/1.0/](http://creativecommons.org/publicdomain/zero/1.0/)) | Yes / Yes / Yes | No (optional) | 90 Hz HPF, active burst trimmed, 3ms/25ms fades, normalized, 48kHz (randomized across all 12 slide+place clips on card play) | 0.086–0.282s, 48kHz, RMS -21.2 to -23.9dB |
| `sfx/trick_collect.ogg` | `kenney_casino-audio/Audio/cards-pack-take-out-2.ogg` ([Kenney Casino Audio v1.1](https://kenney.nl/assets/casino-audio)) | Kenney Vleugels (`kenney.nl`) | **CC0 1.0 Universal** ([creativecommons.org/publicdomain/zero/1.0/](http://creativecommons.org/publicdomain/zero/1.0/)) | Yes / Yes / Yes | No (optional) | 90 Hz HPF, trimmed 0–580ms, 4ms/30ms fades, soft-limited, 48kHz | 0.580s, 48kHz, RMS -19.3dB, Peak -2.8dB |
| `sfx/ui_click.ogg` | `kenney_casino-audio/Audio/chip-lay-3.ogg` ([Kenney Casino Audio v1.1](https://kenney.nl/assets/casino-audio)) | Kenney Vleugels (`kenney.nl`) | **CC0 1.0 Universal** ([creativecommons.org/publicdomain/zero/1.0/](http://creativecommons.org/publicdomain/zero/1.0/)) | Yes / Yes / Yes | No (optional) | 90 Hz HPF, trimmed 80–165ms, 3ms/20ms fades, normalized, 48kHz | 0.085s, 48kHz, RMS -24.2dB, Peak -4.2dB |
| `sfx/trump_select.ogg` | `deck-square-up.wav` + `kenney-interface-sounds/drop_004.wav` | Outta This World Audio + Kenney Vleugels | Royalty-Free + CC0 1.0 | Yes / Yes / Yes | No | Layered card seal + warm confirmation tap, 80 Hz HPF / 5.8 kHz LPF, 48kHz | 0.360s, 48kHz, RMS -22.1dB, Peak -2.8dB |
| `sfx/bid_pass.ogg` | `kenney-interface-sounds/back_004.wav` + `drop_002.wav` ([Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)) | Kenney Vleugels (`kenney.nl`) | **CC0 1.0 Universal** | Yes / Yes / Yes | No | Muted felt/wood tap, 80 Hz HPF / 3.4 kHz LPF, 48kHz (voice `pass.ogg` handles bid pass) | 0.180s, 48kHz, RMS -23.1dB, Peak -4.2dB |
| `sfx/trump_reveal.ogg` | `card-flip-1.wav` + `kenney-interface-sounds/glass_001.wav` + `confirmation_003.wav` | Outta This World Audio + Kenney Vleugels | Royalty-Free + CC0 1.0 | Yes / Yes / Yes | No | Layered card flip + shimmer bell, 80 Hz HPF / 7.2 kHz LPF, 48kHz | 0.460s, 48kHz, RMS -21.4dB, Peak -3.4dB |
| `sfx/turn_alert.ogg` | `kenney-interface-sounds/glass_005.wav` + `back_004.wav` ([Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)) | Kenney Vleugels (`kenney.nl`) | **CC0 1.0 Universal** | Yes / Yes / Yes | No | Soft crystal-wood chime, 80 Hz HPF / 5.2 kHz LPF, 48kHz | 0.240s, 48kHz, RMS -23.0dB, Peak -5.2dB |
| `sfx/error.ogg` | `free-card-game-sounds-audio/card-hover.wav` ([Free Card Game Sounds](https://moneywithjjcom.itch.io/free-card-game-sounds)) | Outta This World Audio (`moneywithjjcom.itch.io`) | **Royalty-Free Commercial Game License** (Bundled `README.md`) | Yes / Yes / Yes (compiled game) | No | 90 Hz HPF, trimmed 0–475ms, 4ms/30ms fades, normalized, 48kHz | 0.475s, 48kHz, RMS -22.0dB, Peak -6.4dB |
| `sfx/card_invalid_drop.ogg` | `free-card-game-sounds-audio/card-invalid-drop.wav` ([Free Card Game Sounds](https://moneywithjjcom.itch.io/free-card-game-sounds)) | Outta This World Audio (`moneywithjjcom.itch.io`) | **Royalty-Free Commercial Game License** (Bundled `README.md`) | Yes / Yes / Yes (compiled game) | No | 90 Hz HPF, active burst trimmed, 3ms/25ms fades, soft-limited, 48kHz | 0.160s, 48kHz, RMS -24.6dB, Peak -2.1dB |
| `voice/hold.ogg`, `double.ogg`, `quadruple.ogg` | Edge Neural Speech (`en-US-ChristopherNeural`) | Microsoft Cognitive Services Neural Voice | Commercial use permitted | Yes / Yes / Yes | No | Matching Pass 22.14 75 Hz HPF, silence trim, -1.5 dBFS / 0.14 RMS, 48kHz | 0.447–0.745s, 48kHz, RMS -17.6 to -19.4dB |
| `sfx/pair_declared.ogg` | `card-flip-1.wav` + `kenney-interface-sounds/confirmation_002.wav` + acoustic triad | Outta This World Audio + Kenney Vleugels + In-house DSP | Royalty-Free + CC0 1.0 | Yes / Yes / Yes | No | Double-flip + ascending royal triad chime, 48kHz | 0.650s, 48kHz, RMS -20.6dB, Peak -5.4dB |
| `sfx/hand_win.ogg` | `kenney-interface-sounds/confirmation_001.wav` + `004.wav` + warm C-maj triad | Kenney Vleugels + In-house DSP | **CC0 1.0 Universal** | Yes / Yes / Yes | No | Warm ascending major triad bell/harp tail, 48kHz | 0.820s, 48kHz, RMS -20.5dB, Peak -7.4dB |
| `sfx/hand_loss.ogg` | `kenney-interface-sounds/minimize_006.wav` + warm descending cadence | Kenney Vleugels + In-house DSP | **CC0 1.0 Universal** | Yes / Yes / Yes | No | Mellow descending wooden cadence, 48kHz | 0.620s, 48kHz, RMS -21.5dB, Peak -7.1dB |
| `sfx/match_win.ogg` | `kenney-interface-sounds/confirmation_004.wav` + `002.wav` + club victory fanfare | Kenney Vleugels + In-house DSP | **CC0 1.0 Universal** | Yes / Yes / Yes | No | Ascending C5–E5–G5–C6 major-9th arpeggio + chime sparkle, 48kHz | 1.420s, 48kHz, RMS -19.5dB, Peak -5.1dB |
| `sfx/match_loss.ogg` | `kenney-interface-sounds/minimize_006.wav` + `008.wav` + minor cadence | Kenney Vleugels + In-house DSP | **CC0 1.0 Universal** | Yes / Yes / Yes | No | Dignified descending minor cadence, 48kHz | 1.120s, 48kHz, RMS -21.0dB, Peak -4.7dB |
