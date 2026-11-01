# Follow MZ

한국의 실시간 키워드, 밈과 유행어, 핫플레이스를 보는 Android Flutter 앱입니다.
Material 3, 시스템 라이트/다크 모드, Riverpod 2, Dio, Shimmer를 사용합니다.
Android API 24 이상 **arm64-v8a 기기 전용**입니다. 패키지 ID: `com.followmz.app`.

## 개발 및 검증

Flutter **3.47.9 stable**, JDK 17, Android SDK 36 및 Flutter가 지정하는 NDK를 사용합니다.
프로젝트의 기존 체크아웃에서 실행하세요. 클라우드 작업은 이미 격리되어 있으므로 별도 worktree는 필요하지 않습니다.

```sh
flutter doctor -v
flutter pub get
dart format lib test
flutter analyze --fatal-infos
flutter test --coverage
python3 -m unittest discover -s scripts -p 'test_*.py' -v
flutter run -d <android-arm64-device-id>
flutter build apk --debug --target-platform=android-arm64
```

`android/local.properties`와 Gradle wrapper 실행 파일/JAR은 Flutter 빌드 시 생성됩니다.
API 36을 compile/target SDK로 사용하고, minSdk는 24입니다.
일반 APK는 NDK ABI 필터를 ARM64로 제한합니다. split APK에서는 AGP 충돌을 피하기 위해
NDK 필터 대신 `--target-platform=android-arm64`로 ABI를 선택합니다.
의존성 버전은 `pubspec.yaml`에 명시되어 있습니다. 의존성 해결 후 생성된
`pubspec.lock`을 커밋해 전이 의존성도 고정하세요.

## 데이터

기본 JSON: `https://raw.githubusercontent.com/ChoiSangJin/trend-follow-app/main/data/trends.json`.
다른 공개 HTTPS JSON을 사용하려면 실행/빌드 시
`--dart-define=TREND_ENDPOINT=https://example.com/trends.json`을 추가하세요.
APK에는 API 비밀키를 넣지 않습니다. 앱은 최대 3회까지 일시적 오류를 재시도하며
5분 메모리 캐시, 강제 새로고침의 캐시 무효화, 8초 연결/12초 응답 제한을 사용합니다.
마지막 성공 데이터는 프로세스가 살아 있는 동안만 보관됩니다. 오프라인 최초 실행은 재시도 화면입니다.
업데이트 시간은 KST로 표시합니다.

`data/trends.json`은 대한민국 Trends 필터 결과와 편집 가이드를 제공합니다. 초기 수집 전 키워드가 비어 있어도 가이드 두 탭은 표시됩니다.
`Refresh Korean trends` Actions가 3시간마다 대한민국 Google Trends RSS를 수집합니다.
수집 성공 시 검증된 대한민국 검색어로 갱신됩니다. RSS 장애나 빈 응답은 기존 파일을 보존하고 작업을 실패 처리합니다.
RSS 제공 상황에 따라 수집이 실패할 수 있으며 스케줄 실행은 GitHub 사정에 따라 지연될 수 있습니다.

밈 및 장소는 출처와 이용 권한을 검토한 항목을 `data/editorial.json`의 `memes`, `hotplaces`에 편집해 제공합니다.
유행어와 장소를 각각 3개 제공하며, 실시간 인기 순위가 아닌 편집 가이드임을 화면에 표시합니다.
서울 도시데이터 API는 아직 연결하지 않았으며 혼잡도나 20대 비율을 만들어 내지 않습니다.
실시간 장소 지표가 필요하면 별도 서버/Actions에서 인증 API를 호출해 이 JSON 스키마에 맞춰 제공하세요.
지도 버튼은 네이버지도/카카오맵 앱 검색을 시도한 뒤 미설치 시 웹 지도로 연결합니다.

## 서명된 APK와 GitHub Release

GitHub 저장소 → Settings → Secrets and variables → Actions에 다음 **repository secrets**를 설정하세요.
키 파일과 비밀번호를 Git이나 채팅에 올리지 마세요. 같은 키를 향후 버전에도 유지하고 안전하게 백업하세요.

| Secret | 용도 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 배포용 JKS 파일의 Base64 인코딩 값 |
| `ANDROID_STORE_PASSWORD` | 키 저장소 비밀번호 |
| `ANDROID_KEY_PASSWORD` | 배포 키 비밀번호 |
| `ANDROID_KEY_ALIAS` | 배포 키 별칭 |

처음 키를 만들 때 안전한 로컬 디렉터리에서 다음 명령을 실행하세요. 비밀번호는 대화형으로 입력합니다.

```sh
keytool -genkeypair -v -keystore follow-mz-release.jks -alias followmz \
  -keyalg RSA -keysize 3072 -validity 10000
```

로컬 release 빌드는 ignored 파일 `android/key.properties`를 만드세요.
`storeFile`은 절대 경로 또는 android 디렉터리 기준 경로입니다.

```properties
storeFile=/secure/path/follow-mz-release.jks
storePassword=<local-only>
keyAlias=followmz
keyPassword=<local-only>
```

```sh
flutter build apk --release --split-per-abi --target-platform=android-arm64
```

서명 정보가 없으면 release 빌드는 실패합니다. 배포본에 debug 서명을 사용하지 않습니다.
PR의 CI가 분석·테스트·ARM64 debug 빌드를 통과한 후 main에 머지하고 버전 태그를 올리세요.

```sh
git switch main
git pull --ff-only origin main
git tag v1.0.0
git push origin v1.0.0
```

`Release ARM64 APK`가 테스트, 서명 빌드, APK 서명 및 ABI 검증을 통과한 뒤 GitHub Release에
`Follow-MZ-arm64-v8a.apk`와 `SHA256SUMS`를 첨부합니다. 태그는 main에 포함된 커밋이며
`pubspec.yaml` 버전과 같아야 합니다. 후속 릴리스는 버전과 태그를 올려주세요.
Actions 실행 번호로 Android build number를 증가시키므로 같은 release workflow를 유지하세요.
APK를 내려받아 체크섬을 확인한 뒤 기기에서 파일을 열고 해당 설치 출처를 허용해 설치합니다.
Google Play 배포와 iOS 빌드는 포함하지 않습니다.

예약 수집의 직접 push가 브랜치 보호 정책에 의해 차단되면 봇의 해당 권한을 허용하거나
별도 데이터 저장소/PR 기반 발행 절차로 전환해야 합니다. Actions를 통한 PR 생성 옵션은 앱 빌드에 필요하지 않습니다.

## 1.0.1 데이터 정정

Google Trends RSS 요청은 `geo=KR&hl=ko`로 고정하고 응답 channel/link의
`geo=KR`도 검증합니다. 다른 지역이나 지역 정보가 없는 피드는 거부합니다.
한글 포함 및 검색량 1천 회 이상 조건을 적용해 저검색량 해외 경기 잡음을 줄입니다.
이것은 대한민국 지역의 급상승 검색 목록이며 전국 전체 검색량 순위가 아닙니다.
외국 주제도 대한민국에서 관심이 높으면 포함될 수 있습니다. 검색자의 국적은 알 수 없습니다.
조건을 만족하는 항목이 없거나 수집 실패 시 이전 피드를 유지하고 작업은 실패합니다.

밈 탭은 편집 유행어 사전, 장소 탭은 서울 장소 가이드로 각각 3개 항목을 제공합니다.
실시간 인기 순위나 현장 통계가 아닙니다. 유행어에는 우리말샘 검색 링크,
장소에는 지도 검색을 제공합니다. 혼잡도·20대 비율은 미제공으로 표시합니다.
