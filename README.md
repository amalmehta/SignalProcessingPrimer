# Signal Processing Primer

A course on signal processing for audio, images, video and film, as a Mac app and a website. It has 13 lessons, and each one has a demo you can play with and listen to, plus a short quiz.

**Website:** [claude.ai/artifact/4mZjs9pvjHnj2D5RcxiPtu](https://claude.ai/artifact/4mZjs9pvjHnj2D5RcxiPtu) (private until you share it)

![Sampling and Aliasing lesson in the Mac app](docs/images/lesson-sampling.jpg)

![The website's course overview](docs/images/web-welcome.jpg)

| Spectrograms | Filter design | Image kernels |
|---|---|---|
| ![Spectrogram demo](docs/images/lesson-spectrogram.jpg) | ![Filter demo](docs/images/lesson-filters.jpg) | ![Image kernels demo](docs/images/lesson-images.jpg) |
| **Compression (DCT)** | **Compressor** | **Frame rate and shutter** |
| ![JPEG demo](docs/images/lesson-jpeg.jpg) | ![Compressor demo](docs/images/lesson-dynamics.jpg) | ![Wagon-wheel demo](docs/images/lesson-film.jpg) |
| **Colour, gamma and white balance** | **Colour gamuts** | |
| ![Colour and gamma demo](docs/images/lesson-colour.jpg) | ![Gamut diagram](docs/images/lesson-colour-gamut.jpg) | |

```mermaid
flowchart LR
    A["Foundations<br/>signals · sampling · bit depth"] --> B["Frequency domain<br/>FFT · windows · spectrograms"]
    B --> C["Filtering<br/>convolution · EQ · compressors"]
    C --> D["Images, video and film<br/>2-D filters · DCT/JPEG · frame rate and shutter · colour, gamma, white balance and gamuts"]
```

**Links:** [Website](https://claude.ai/artifact/4mZjs9pvjHnj2D5RcxiPtu) · [Setup and use](docs/INSTRUCTIONS.md) · [System design](docs/SYSTEM-DESIGN.md) · [File structure](docs/FILE-STRUCTURE.md) · [Original brief](signal_processing_primer.md)
