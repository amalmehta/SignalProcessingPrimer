# Signal Processing Primer

A Mac app that teaches signal processing for audio, images, video and film. It has 12 lessons, and each one has a demo you can play with and listen to, plus a short quiz.

![Sampling and Aliasing lesson](docs/images/lesson-sampling.jpg)

| Spectrograms | Filter design | Image kernels |
|---|---|---|
| ![Spectrogram demo](docs/images/lesson-spectrogram.jpg) | ![Filter demo](docs/images/lesson-filters.jpg) | ![Image kernels demo](docs/images/lesson-images.jpg) |
| **Compression (DCT)** | **Compressor** | **Frame rate and shutter** |
| ![JPEG demo](docs/images/lesson-jpeg.jpg) | ![Compressor demo](docs/images/lesson-dynamics.jpg) | ![Wagon-wheel demo](docs/images/lesson-film.jpg) |

```mermaid
flowchart LR
    A["Foundations<br/>signals · sampling · bit depth"] --> B["Frequency domain<br/>FFT · windows · spectrograms"]
    B --> C["Filtering<br/>convolution · EQ · compressors"]
    C --> D["Images, video and film<br/>2-D filters · DCT/JPEG · frame rate and shutter"]
```

**Links:** [Setup and use](docs/INSTRUCTIONS.md) · [System design](docs/SYSTEM-DESIGN.md) · [File structure](docs/FILE-STRUCTURE.md) · [Original brief](signal_processing_primer.md)
