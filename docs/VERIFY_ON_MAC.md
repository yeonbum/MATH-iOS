# iOS 검증 체크리스트

1. GitHub Actions에서 `scripts/build_ios.sh`가 `a2b3018` XCFramework 빌드를 성공하는지 확인합니다.
2. Xcode `xcodebuild` SwiftUI 컴파일 및 링킹 오류가 없도록 수정합니다.
3. Simulator에서 홈, 앨범, 저장/검색, 설정 UI를 확인합니다. iOS Simulator는 실제 카메라와 RAM/GPU 성능을 대표하지 않습니다.
4. 실기기 설치 및 코드 서명이 필요하며, 현재 CI는 서명하지 않습니다.
5. 원본 Qwen GGUF/mmproj 파일을 Files로 넣고, `mate_load` 성공 여부 확인합니다.
6. 동일 이미지/프롬프트로 Android와 iOS 첫 결과 비교: 이미지 인식률, 수식 표현, 답변 일관성, EOS 종료, 후속 질문 맥락.
7. iPhone 실측: Vision encode, image prefill, text prefill, TTFT, 최종 응답, 최대 RSS, 발열/배터리.
8. 앱 백그라운드 전환/대화 변경/메모리 경고 시 안정성 확인.
9. 모델 배포/이용약관/개인정보처리방침/App Store 필수 항목 확인.
