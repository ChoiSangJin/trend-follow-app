# 말문 — 한국 넷플릭스에서 뭐 볼까?

한국 넷플릭스 공식 주간 Top 10을 살펴보고 보고 싶은 작품을 고르는 Android 앱입니다. 4.0.0부터 뉴스·스몰토크 중심 홈을 작품 탐색으로 바꿨습니다. 앱 ID `com.malmun.app`과 기존 서명은 유지합니다. Netflix가 운영하거나 인증한 앱은 아닙니다.

## 화면과 데이터

- 한국 Top 10: TV 프로그램·영화 각 10개, 집계 기간, 이전 주 대비 상승·하락, 첫 진입·재진입, 누적 진입 주수
- 최근 최대 4주 선택, 한글·원제 검색, 확인된 분류 필터. 필터를 적용해도 공식 순위 번호를 유지합니다.
- 작품 상세: 출처가 있는 소개·이미지·분류, 공식 페이지 링크. 확인하지 못한 항목을 만들거나 다른 작품으로 채우지 않습니다.
- 내 목록: 보고 싶은 작품·본 작품을 기기에 저장. 기사 질문 세트와 정답형 퀴즈는 새 홈에 사용하지 않습니다.
- 기존 뉴스 보관함과 메모는 내 목록 하단에서 열 수 있습니다. 기존 저장 키는 수정하지 않습니다.
- 오프라인: 마지막 정상 차트 또는 APK에 포함한 실제 차트를 사용하고 저장된 자료임을 표시합니다. 14일이 지난 집계에는 오래된 자료 안내를 표시합니다. 가짜 순위·연습용 작품을 만들지 않습니다.

‘한국’은 한국에서의 시청 순위를 뜻하며 한국 제작 작품만을 의미하지 않습니다. TV 순위에는 드라마·예능·애니 등이 함께 포함됩니다. 주간 순위를 실시간 순위·국내 전체 OTT 인기·시청자 수·작품의 완성도로 바꾸어 설명하지 않습니다. 누적 진입 주수는 연속 진입 주수가 아닙니다.

## 수집과 출처

`python3 scripts/collect_netflix.py`는 Netflix Tudum의 공식 국가별 TSV와 공개된 한국 차트 페이지를 확인하여 `data/netflix-kr-v1.json`을 만듭니다.

- TSV: https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv
- 한국 TV 차트: https://www.netflix.com/tudum/top10/south-korea/tv
- 한국 영화 차트: https://www.netflix.com/tudum/top10/south-korea

공개 페이지가 TSV보다 최신일 때 TV·영화가 같은 주간인지, 한국 국가 순위가 맞는지, 각 1~10위가 완전한지 확인한 뒤 사용합니다. 공개 HTML에 이미 포함된 JSON만 읽으며 JavaScript를 실행하거나 비공개 API를 호출하지 않습니다. 제목과 시즌이 정확히 같은 항목만 이전 주와 비교합니다. 불완전한 최신 TSV와 역행하는 수집 결과는 발행하지 않습니다. 공개 페이지 구조가 바뀌면 정상 TSV 또는 마지막 발행 자료를 보존합니다.

작품 소개는 공식 한국어 작품 페이지 또는 Tudum의 공개 소개에서 가져옵니다. 한국어 소개가 없는 항목의 초기 번역은 `data/netflix-editorial.json`에 편집하여 두었습니다. 원문·작품·시즌이 정확히 일치할 때만 적용하고 ‘Netflix 공식 소개 · 말문 번역’으로 표시합니다. 새 작품에 확인된 번역이 없으면 영문임을 명시하여 원문을 보여줍니다. 시청 경험·평가·인기 원인을 생성하지 않습니다. `netflix-metadata.json`은 이미 확인한 한국어 정보, `netflix-title-links.json`은 확인한 시리즈 공식 링크를 보완합니다. 회차 줄거리와 결말을 수집하지 않습니다.

기존 `.github/workflows/trends.yml`의 6시간 갱신 작업과 기존 저장소 권한을 유지하며 넷플릭스 JSON을 함께 갱신합니다. 구버전 앱의 뉴스 피드도 계속 갱신합니다. 별도 `netflix.yml` 검증 작업은 읽기 전용이며 결과를 artifact로 제공합니다. API 키·유료 모델·새 인증 권한이 필요하지 않습니다. 외부 공개 자료의 가용성과 재사용 조건은 제공처 정책을 따릅니다.

## 개발과 검증

Flutter 3.47.9 stable · JDK 17 · Android SDK 36. Android 7.0(API 24)+ ARM64 대상입니다.

```sh
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test --reporter expanded
python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/collect_netflix.py
bash scripts/prepare_test_key.sh
flutter build apk --debug --target-platform=android-arm64
```

기본 데이터 주소는 이 저장소 main의 `data/netflix-kr-v1.json`입니다. `NETFLIX_ENDPOINT` dart-define으로 HTTPS JSON 주소를 바꿀 수 있습니다. `assets/netflix-kr.json`은 확인하여 소스에 커밋한 오프라인 스냅샷이며, 빌드 중 임의로 교체하지 않습니다. 최종 main CI에서 실제 수집과 APK 빌드를 검증합니다.

새 저장 키는 `netflix-chart-v1`과 `netflix-library-v1`입니다. 기존 `saved-topics-v2`, `conversation-learning-v1`은 보존합니다. 내 목록 쓰기는 순서대로 처리하고 실패하면 이전 상태를 유지합니다. 개인 기록은 서버로 보내지 않습니다.

## 테스트 APK 배포

`Publish tested APK` 워크플로는 성공한 main CI의 `malmun-debug-arm64` artifact를 사용합니다. 버전 태그와 APK 입력 소스가 같은지, 앱 ID·버전·최소 Android 버전·ARM64 ABI 및 기존 v2.0.0과의 서명 일치를 확인하고 `Malmun-arm64.apk`, `SHA256SUMS`, 설치 안내를 GitHub prerelease로 게시합니다. 관리형 개발용 서명 키는 기존 `malmun-managed-test-signing-v1` 캐시를 그대로 사용합니다. 키 파일은 Git이나 Release에 게시하지 않습니다. 캐시가 만료되거나 삭제되면 서명이 달라질 수 있으므로 영구적인 배포 키 보관을 대체하지 않습니다.

별도 영구 배포 키를 사용할 때만 `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` secrets와 `Release ARM64 APK` 워크플로가 필요합니다. 기본 테스트 APK 배포에는 필요하지 않습니다.
