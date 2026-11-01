# 말문 — 오늘의 스몰토크

최근 한국어 기사에서 대화 소재를 선별하고, 질문과 맥락을 함께 제공하는 Android 앱입니다.
이전 Follow MZ와 별개 앱이며 패키지 ID는 `com.malmun.app`, 버전은 2.1.0입니다.

## 사용자 경험

- 오늘의 말문: 문화·예술, 연예, 스포츠, 기술·과학, 사회에서 각각 최대 2개씩 총 최대 10개의 소재, 주제 필터
- 대화 준비: 기사 제목, 최근 보도된 이유, 질문 복사, 대화 시 참고점, 원문 링크 및 발행 시각
- 보관함: 소재와 질문을 로컬에 저장하여 재실행 후에도 열람
- 오프라인: 마지막 성공 브리핑을 저장. 최초 접속 실패 시에는 ‘대화 연습 모드’를 명시한 기본 질문 제공
- 시스템 라이트/다크 테마, 큰 글꼴, 모바일 화면에서 가변 높이 카드
- 청록색과 크림색 말풍선 아이콘, 코랄색 보조 말풍선

## 정보의 범위와 정확성

Google 뉴스 한국판의 주제별 RSS를 사용합니다. 한국어 언어 코드와 한국판 `ceid=KR:ko`를 확인하고,
최근 72시간 이내 기사만 선택하고 출처의 publisher URL을 명시한 언론사 도메인 목록과 대조합니다. 중복·일부 민감 주제·증시 소재를 필터링하며 각 분야에서 최대 2개를 선정합니다.
문화·예술은 전시·공연·책, 연예는 공개된 신작·활동, 사회는 제도·교통·교육 등 일상에 연결되는 소식 위주로 선별합니다. 자동차 등 산업 전시를 문화·예술로 넣지 않고, 연예는 작품·활동 제목이 확인되는 기사로 좁힙니다. 기술·과학에서 투자·펀드 기사를, 사회에서 의회 일정·해외 행사 홍보를 제외합니다.
필터는 완전한 안전성이나 편집 품질을 보장하지 않으므로 원문을 확인하세요.

**인기 순위, 인스타·틱톡의 실시간 밈 순위, 기사 본문을 읽은 AI 요약을 제공하지 않습니다.**
기사 제목만 확인 가능한 현재 수집 방식에서는 제목을 그대로 전달하고 ‘제목 기반 정보’임을 표시합니다.
질문과 참고점은 분야별 편집 템플릿이며 취재된 사실로 제시하지 않습니다.
정확한 본문 요약이 필요하면 이용 허가된 원문 소스 또는 별도 편집 검수를 추가해야 합니다.

6시간마다 Actions가 피드를 갱신합니다. 적합한 기사가 부족하면 10개 미만이 될 수 있으며
전부 실패하면 마지막 정상 피드를 보존합니다. 오래된 피드는 앱에서 이전 브리핑으로 표시합니다.
실제 기사 발행 시각과 수집 시각을 구분하며 KST로 표시합니다.
API 비밀키나 유료 모델 없이 작동합니다. 공개 피드의 가용성에 따라 수집이 실패할 수 있습니다.

## 개발 및 테스트

Flutter 3.47.9 stable, JDK 17, Android SDK 36, Flutter 지정 NDK.
기존 체크아웃을 사용하세요. 클라우드 작업은 격리되어 있어 별도 worktree는 필요하지 않습니다.

```sh
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test --reporter expanded
python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/collect_briefing.py
bash scripts/prepare_test_key.sh
flutter build apk --debug --target-platform=android-arm64
```

Android 7.0(API 24)+ ARM64용입니다. `BRIEFING_ENDPOINT` dart-define으로 HTTPS JSON 주소를 교체할 수 있습니다.
기본 주소는 이 저장소 main의 `data/briefing-v3.json`입니다. 오프라인 연습은 `assets/practice.json`이며
실제 기사로 표시하지 않습니다. 커밋된 pubspec.lock으로 전이 의존성을 고정하며 CI metadata artifact에서도 확인할 수 있습니다.

기존 화면의 PageStorage에 펼침 상태(bool)와 스크롤 위치(double)가 같은 키로 저장될 수 있는
구조를 제거했습니다. 펼침 위젯 대신 독립 상세 화면을 사용하고 목록별 스크롤 키를 분리했습니다.
화면 전환·보관·필터·상세 뒤로 가기·큰 글꼴 회귀 테스트로 검증합니다.

## 배포

`Publish tested APK`를 수동 실행하여 성공한 **main CI**의 run_id와 태그를 지정합니다.
테스트한 소스와 태그 일치, APK 서명, 기존 말문 v2.0.0과의 서명 일치, arm64-v8a ABI를 검증한 뒤 Release에 APK·SHA256SUMS를 첨부합니다.
`Malmun-arm64.apk`는 개발용 서명 배포본입니다. 기존 Follow MZ와 패키지 ID가 달라 동시에 설치 가능합니다.

main CI는 `android/.test-signing/debug.keystore`를 고정된 Actions cache key로 재사용합니다.
Gradle debug 서명도 이 파일을 직접 가리키며 CI에서 파일이 없으면 빌드를 중단합니다.
표준 Android debug 비밀번호를 사용하는 테스트용 키이며, 키 파일은 Git이나 Release에 넣지 않습니다. 캐시가 유지되는 동안 후속 업데이트의
서명이 유지됩니다. 캐시 만료/삭제 후에는 서명이 바뀔 수 있으므로 영구적인 배포 키 보관을 대체하지 않습니다.
최초 배포는 main CI의 빌드를 사용해 main 캐시에 키를 남깁니다.

별도 영구 배포 키를 사용할 경우 `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`,
`ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` repository secrets가 필요하며,
`Release ARM64 APK`를 버전 태그 ref에서 수동 실행합니다. secrets 값은 Git에 넣지 마세요.
이 배포 경로는 기본 테스트 배포에 필요하지 않습니다.

구버전 앱을 위해 `data/briefing.json`에는 schema_version 2와 최대 5개를 유지합니다.
새 앱은 schema_version 3에서 분야별 2개·총 10개 제한을 검사합니다. 기존 보관함은 유지하고 이전 분야 이름도 보관함 필터에서 그대로 열 수 있습니다.
