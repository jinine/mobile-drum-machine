# cpm0003

drum machine

![1](https://github.com/jinine/mobile-drum-machine/blob/main/Screenshot_20250624_032120.png)


## ✨ Features

A few resources to get you started if this is your first Flutter project:

---

## 🔧 Architecture

- **Flutter**: UI, state management, gesture handling, platform coordination
- **Native Audio (via FFI)**:
    - **Playback**: `just_audio` or native audio engines
    - **Effects & DSP**: C++ audio libraries (e.g. [RubberBand](https://breakfastquay.com/rubberband/), [SoundTouch](https://www.surina.net/soundtouch/))
    - **Audio routing**: AVAudioEngine / AudioTrack

---

## 📁 Project Structure

```plaintext
/lib
  ├── main.dart
  ├── screens/
  ├── widgets/
  ├── models/
  └── services/
    
/assets
  └── samples/
```