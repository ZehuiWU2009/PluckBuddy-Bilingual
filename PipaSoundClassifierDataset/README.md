# PipaSoundClassifier Dataset

A small collection of audio clips I recorded and gathered to train an on-device
sound classifier for my Pipa practice app — a personal exploration of audio
machine learning on iOS. The classifier acts as a gate: it decides whether the
microphone is hearing a Pipa, another instrument, speech, or just background
noise, so the app only runs pitch and fingering analysis on actual Pipa playing.

This repository holds the **training audio** behind that model
(`PipaSoundClassifier.mlmodel`). It is shared so the experiment is reproducible
and the recording process is documented.

## Embedded in PluckBuddy-Bilingual

This dataset is bundled as a subfolder named `PipaSoundClassifierDataset/` inside the [PluckBuddy-Bilingual](https://github.com/ZehuiWU2009/PluckBuddy-Bilingual) app project. Because it was recorded and built exclusively for that app, the folder travels with the app's source tree. The real 627 MB of audio is kept in this standalone repository (tracked with Git LFS) so that the app repository itself stays lightweight; the app's README links back here.

## What is inside

Four folders, one per class:

| Folder             | What it contains                                                                                              | Approx. size |
| ------------------ | ------------------------------------------------------------------------------------------------------------- | ------------ |
| `pipa/`            | My own Pipa playing — different fingering techniques (pluck, roll, sweep, long tones) and Pipa pieces I performed on stage. | ~40 MB       |
| `other_instrument/`| Instruments I play myself: drum kit I drummed, guitar, zhongruan and piano I played, and songs I sang. My grandfather's harmonica playing is also put to use here — it is the clip
`Melodica.m4a`. Because I do not play guzheng, three guzheng pieces from the Mid-Autumn set were AI-generated and added in, to avoid publishing anyone else's recording. Ten of the clips (drum / guitar / zhongruan / voice+piano) were captured on video and kept as `.m4a` files that carry **both** an AAC audio track and a video track re-encoded to 640x480, so the performance stays visible as well as audible. | ~430 MB      |
| `speech/`          | My own voice — classroom talks and debate-competition speeches, recorded as a contrast to Pipa timbre. `speech01-03.m4a` also keep a 640x480 video track. | ~154 MB      |
| `background/`      | Everyday environmental noise — ambience from inside my home (e.g. the air conditioner) and street noise captured out on the road. | ~4 MB        |

All clips are either self-recorded by the author, contributed by family
(recorded with permission), or AI-generated; everything is cleared for public
sharing. Total: 37 clips (~627 MB), in `.m4a` / `.mp3`.

The thirteen video-derived clips are stored with Git LFS. Their video tracks are
downscaled to 640x480 to keep the repository manageable — they are kept purely
for documentation (showing that the recordings really are performances on those
instruments), while training consumes only the audio.

## From raw recording to training sample

The hardest part of building this dataset was **collecting the instrument
sounds** — but it helped that I play quite a few instruments. Every clip,
whatever its source, goes through the same sampling pipeline before it can train
the model:

1. **Capture** at the device sample rate (typically 48 kHz), mixed down to mono.
2. **Downsample** to **16 kHz** with linear interpolation.
3. **Slice** into **15,600-sample windows (~0.975 s)**, advanced with **50% overlap** so neighbouring windows share half their samples.
4. **Feed the raw waveform** — not a spectrogram, not hand-made features — straight into the classifier.

This pipeline is applied uniformly to every raw recording, whether it is a Pipa
phrase, a drum fill, a debate speech or roadside noise. The video tracks are
never used for training; they exist only so a viewer can confirm what was
actually played. The released model window is 15,600 frames at 16 kHz, matching
the clips here.

## Reproducing the training

1. Place the four class folders as shown above.
2. Apply the preprocessing: mono, 16 kHz, 15,600-sample windows at 50% overlap.
3. Train a 4-class audio classifier (e.g. Create ML's Sound Classifier, or an
   equivalent small CNN on raw waveforms) with the four labels
   `pipa`, `other_instrument`, `speech`, `background`.
4. Export to Core ML as `PipaSoundClassifier.mlmodel`.

The app pairs this gate with a Vision-based fingering classifier (pluck / roll /
sweep) and audio analysis to give feedback during practice.

## License

Released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
See `LICENSE`.

---

# PipaSoundClassifier 数据集

这是我为自己的琵琶练习 App 录下来、收集来的一小批音频，用来训练一个端侧声音
分类器——一次关于 iOS 音频机器学习的个人探索。这个分类器像一道门：它先判断
麦克风听到的是琵琶、别的乐器、人声，还是单纯的环境噪音，这样 App 只在真的在
弹琵琶时才去做音高和指法的分析。

这个仓库里放的就是那个模型（`PipaSoundClassifier.mlmodel`）背后的**训练音频**。
把它公开，是为了让这个实验可以复现，也把录音的过程记录下来。

## 内嵌于 PluckBuddy-Bilingual

本数据集作为子文件夹 `PipaSoundClassifierDataset/` 随 [PluckBuddy-Bilingual](https://github.com/ZehuiWU2009/PluckBuddy-Bilingual) 应用工程一起发布。因为它专为这个 App 录制、目前只供这一个应用使用，所以跟着工程源码走。627 MB 真实音频仍留在这个独立仓库里（用 Git LFS 跟踪），这样应用仓库本身保持轻量；应用工程的 README 会反向链接到本仓库。

## 里面有什么

按四个类别分了四个文件夹：

| 文件夹             | 内容                                                                                              | 大约大小 |
| ------------------ | ------------------------------------------------------------------------------------------------- | -------- |
| `pipa/`            | 我自己弹的琵琶——不同指法的练习（弹挑、轮指、扫弦、长音），还有我在舞台上弹的琵琶乐曲。            | 约 40 MB |
| `other_instrument/`| 我自己会演奏的乐器：我打的架子鼓，弹的吉他、中阮、钢琴，还有自己唱的歌。我爷爷吹的口琴声，我也把它利用了起来（就是 `Melodica.m4a` 这一段）。古筝我不会弹，为了避免侵权，就用了 AI 生成的三段中秋古筝曲加进来。其中有十段（鼓、吉他、中阮、人声+钢琴）是录了视频的，保留成同时带 AAC 音轨和 640x480 视频轨的 `.m4a`，既能听也能看到演奏画面。 | 约 430 MB |
| `speech/`          | 我自己的声音——课堂上的发言，还有辩论赛的发言，用来和琵琶的音色作对比。`speech01-03.m4a` 同样保留了 640x480 视频轨。 | 约 154 MB |
| `background/`      | 日常的环境噪音——家里录的环境声（比如空调），还有在马路上录到的街边噪音。                          | 约 4 MB  |

所有片段要么是作者本人录制，要么是家人录制（已获授权），要么是 AI 生成，都可以
公开发布。一共 37 段（约 627 MB），格式为 `.m4a` / `.mp3`。

这十三段带视频的片段用 Git LFS 存储，视频轨统一降到 640x480 以控制仓库体积——
它们纯粹是为了留档（证明这些录音确实是那些乐器上的演奏），训练时只用音频。

## 原始录音如何变成训练样本

做这个数据集最难的一步，就是**收集各种乐器的声音**——好在我会的乐器多，才凑得齐。
不管来源是什么，每段录音在进入模型之前，都要经过同一套采样流程：

1. **采集**：用设备的采样率（通常是 48 kHz）录下，并混为单声道。
2. **降采样**：用线性插值降到 **16 kHz**。
3. **切片**：切成 **15,600 个采样点（约 0.975 秒）** 的窗口，窗口之间以 **50% 重叠**推进，相邻窗口共享一半样本。
4. **喂原始波形**：直接把原始波形送进分类器——不是频谱，也不是手工提取的特征。

这套流程对每一段原始录音一视同仁：无论是一句琵琶、一通鼓点、一段辩论发言，还是
马路边的噪音，都按同样的方式处理。视频轨从不参与训练，它存在的唯一意义，是让看
的人能确认当时到底弹了什么。发布出来的模型窗口就是 16 kHz 下的 15,600 帧，和这里
的片段一致。

## 复现训练

1. 按上面的结构放好四个类别的文件夹。
2. 套用上面的预处理：单声道、16 kHz、15,600 采样点窗口、50% 重叠。
3. 训练一个四分类音频分类器（比如用 Create ML 的 Sound Classifier，或等价的、直接吃
   原始波形的小型 CNN），四个标签为 `pipa`、`other_instrument`、`speech`、`background`。
4. 导出为 Core ML 模型 `PipaSoundClassifier.mlmodel`。

App 把这道门和基于 Vision 的指法分类器（弹挑 / 轮指 / 扫弦）以及音频分析配合起来，
在练习时给出反馈。

## 许可

基于 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 发布。详见 `LICENSE`。

---

*Personal project — grown out of my own Pipa practice, still evolving.*
