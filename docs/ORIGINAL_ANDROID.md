# 기존 Android와의 관계

현재 Android 프로젝트 KKPGwen은 수정하지 않습니다. 본 iOS 프로젝트는 독립적으로 빌드됩니다.

참조한 원본 Android 코드:
- `MATE_v1_2_Settings_Clash_Fixed_FULL.zip`: Compose UI, 카메라 화면 연계, SQLite 기록·즐겨찾기, 설정, MathAnswerView.
- `SolveMate_FirstImage_Optimization.zip`: `solvemate_jni.cpp`, 이미지 프로파일링, mtmd 이미지 프리필·multi-turn.

모델 파일이 아닌 코드 흐름만 참조했으며, 기존 GGUF 파일 자체는 패키지에 포함하지 않았습니다.

현재 Kotlin Multiplatform 공통 UI **미이관**. 향후 Android 전체 `build.gradle.kts`, `AndroidManifest.xml`, `CameraScreen.kt`, `ProblemCropScreen.kt`, `NativeVlmBridge.kt`, `CMakeLists.txt`가 확보되면 공통 UI/도메인 분리를 진행합니다.
