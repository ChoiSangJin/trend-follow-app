# 말문 — 넷플릭스와 애니, 지금 뭐 볼까?

한국 넷플릭스 공식 주간 Top 10을 살펴보고 보고 싶은 작품을 고르는 Android 앱입니다. 4.0.0부터 뉴스·스몰토크 중심 홈을 작품 탐색으로 바꿨습니다. 앱 ID `com.malmun.app`과 기존 서명은 유지합니다. Netflix가 운영하거나 인증한 앱은 아닙니다.

## 4.1 애니 탭

상단 **넷플릭스 / 애니** 탭으로 전환합니다. 시작 화면은 넷플릭스이며 애니 데이터는 처음 탭을 열 때 불러옵니다. 넷플릭스 개인 목록과 기존 기록은 그대로 사용할 수 있습니다.

- 방영 중 관심순: AniList의 `TRENDING_DESC` 순서입니다. 해외 커뮤니티 활동 지표이며 한국 시청 순위가 아닙니다. 100점 만점 평점은 순위와 별도로 표시합니다.
- 분기 신작: 한국 시각 기준 현재 분기의 작품을 AniList 등록 이용자 수순으로 확인합니다. 한국 OTT 제공 여부는 확인하지 않습니다.
- 소식: Anime News Network RSS의 최근 90일 이내 기사 최대 15개와 AniList의 향후 14일 방영 예정·제공 예고편을 출처별로 표시합니다. 예고편 게시일은 API가 제공하지 않아 최신 뉴스로 표현하지 않습니다. 기사 수집 실패는 따로 표시합니다.
- 제목·소개·기사는 제공처 원문입니다. 검증하지 않은 한국어 제목이나 번역을 만들지 않습니다. 작품 상세에서 원문·이미지·분류와 제공처 링크를 확인합니다.
- 별도 캐시 `anime-chart-v1`와 실제 응답을 담은 번들 `assets/anime.json`으로 오프라인을 지원합니다. 48시간이 지난 수집 자료는 오래된 자료임을 표시하며, 수집 시각이 역행하는 응답은 저장하지 않습니다.

수집: `python3 scripts/collect_anime.py`. API: https://graphql.anilist.co · 문서/이용조건: https://docs.anilist.co/ · 기사 RSS: https://www.animenewsnetwork.com/news/rss.xml . 공개 API에 키가 필요하지 않습니다. AniList 무료 사용 조건(비상업/월 수익 150달러 미만 등)과 경쟁 목록·추적 서비스 제한을 배포·수익화 변경 전에 재검토해야 합니다. 애니 목록 추적 기능은 제공하지 않습니다. 소식 원문은 제공처에서 열며 출처와 링크를 유지합니다.

기존 6시간 갱신 작업에서 애니 피드도 갱신합니다. Netflix와 AniList 중 한쪽의 실패가 다른 정상 피드의 발행을 막지 않으며, 실패 자체는 작업 결과에 표시합니다. `anime.yml`은 읽기 전용 소스 검증 작업입니다.

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

별도 영구 배포 키를 사용할 때만 `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` secrets와 `Release ARM64 APK` 워크플로가 필요합니다. 기본 테스트 APK 배포에는 필요하지 않습니다.

정식 APK는 `Release ARM64 APK`에서 버전 태그를 선택하여 빌드합니다. 버전 코드는 `pubspec.yaml` 값을 사용하며 CI 실행 횟수로 덮어쓰지 않습니다. 릴리즈 모드·앱 ID·버전·최소 SDK·ARM64와 서명을 확인하고 공개 인증서 SHA-256을 `SIGNING.txt`에 게시합니다. 정식 키가 기존 테스트 키와 다르면 업데이트 설치가 불가능하며, 기존 앱 삭제 시 개인 목록과 메모가 사라질 수 있습니다. 비밀키와 비밀번호는 Release에 포함하지 않습니다.

서명 준비 단계에서 `keytool`로 키 파일·저장소 비밀번호의 일치와 alias 존재 여부를 검사합니다. `keystore password was incorrect`는 키 파일과 `ANDROID_KEYSTORE_PASSWORD`를 짝으로 다시 확인해야 한다는 뜻입니다. `ANDROID_KEY_PASSWORD`는 개인 키 비밀번호로 별개입니다. 도구 출력과 비밀값을 오류 요약에 넣지 않습니다. 키 파일과 비밀번호는 채팅에 올리지 말고 GitHub Secrets에서 수정하세요.

Flutter ARM64 분리 릴리즈 APK의 Android 버전 코드는 `pubspec` 빌드 번호에 ABI 보정값 2000을 더한 값입니다(4.1.1+10 → 2010). 검증에서 이 값을 확인합니다.
