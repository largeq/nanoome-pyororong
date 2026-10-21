# 프네 표변환

한글 for Mac에서 복사한 표를 네이버 카페 에디터에 붙여넣을 수 있도록 HTML을 변환하는 macOS 메뉴바 앱입니다.

이 폴더는 **Swift 기반의 독립 프로젝트**입니다. 기존 Python 버전은 `/Users/jeonggeungyu/PythonProjects/phronesis_pyo/`에 별도로 보존되어 있습니다. 이 프로젝트의 빌드·테스트·실행은 해당 Python 폴더에 의존하지 않습니다.

## 실행

1. `프네 표변환.app`을 실행합니다.
2. 한글에서 **표만** 선택해 `⌘C`로 복사합니다.
3. 메뉴바의 표 아이콘을 클릭하고 **표 변환하기**를 선택합니다.
4. 완료 알림을 확인하고 네이버 카페 편집 화면에 `⌘V`로 붙여넣습니다.
5. 메뉴바의 **종료**로 앱을 종료합니다.

첫 변환 시 알림 권한을 요청합니다. 알림을 허용하지 않으면 대화상자로 결과를 표시합니다. 붙여넣은 표의 너비는 카페 에디터에서 조정해야 할 수 있습니다.

앱 실행에는 Python이나 Xcode가 필요하지 않습니다. 앱의 변환 기능은 로컬에서 실행되며 표 내용을 서버로 전송하지 않습니다.

## 개발 환경과 빌드

- Swift 버전의 최소 대상: **macOS 12 Monterey**
- 검증한 개발 도구: **Xcode 27.1 / Swift 6.4**
- 의존성: **SwiftSoup 2.14.3** — Swift Package Manager로 관리
- Release 앱은 Apple Silicon(`arm64`)과 Intel(`x86_64`) 코드를 함께 포함합니다.

기존 Python 안내의 macOS 10.15 요구사항은 Swift 버전에 적용되지 않습니다. 현재 Xcode SDK와 선택한 SwiftSoup 릴리스의 지원 범위에 맞춰 최소 대상을 macOS 12로 설정했습니다. 구형 macOS와 Intel 하드웨어에서의 실제 실행 검증은 별도로 필요합니다.

Xcode에서 `PhronesisPyo.xcodeproj`를 열고 `PhronesisPyo` scheme과 `My Mac` 실행 대상을 선택하면 개발할 수 있습니다.

터미널에서는 프로젝트 루트에서 실행합니다.

```sh
bash scripts/build-app.sh
```

생성되는 앱:

```text
.build/xcode/Build/Products/Release/프네 표변환.app
```

`프네 표변환.command`와 `프네 표변환 (백그라운드).command`도 위 앱을 실행합니다. 앱이 없으면 먼저 빌드하므로, 이 실행 방식에는 Xcode가 필요합니다. 소스를 수정한 후에는 다시 빌드해야 합니다.

`배포용 패키지 만들기.sh`는 앱을 빌드하고 `.build/프네표변환_Swift_v1.0.0.zip`을 만듭니다. 현재 앱은 **로컬 실행용 ad-hoc 서명**을 사용합니다. GitHub 공개 배포를 위한 Developer ID 서명·Apple 공증·자동 업데이트는 아직 구성하지 않았습니다.

## 코드 구조

- `App/`: 앱 생명주기, 메뉴바, 변환 결과 알림
- `Sources/TableConverterCore/`: 한글 HTML 분석과 네이버용 HTML 생성
- `Sources/TableConverterMac/`: macOS 클립보드 읽기·쓰기
- `Tests/`: Python 결과와의 비교, 변환 경계 사례, 별도 테스트용 클립보드 검증
- `Package.swift`, `Package.resolved`: 라이브러리와 고정된 의존성 버전

메뉴바는 AppKit으로 구현했습니다. 이후 SwiftUI로 설정·사용 안내 화면을 추가할 때 변환 모듈과 클립보드 모듈을 그대로 사용할 수 있도록 분리했습니다. 해당 화면들은 이번 전환에 포함하지 않았습니다.

## 검증

```sh
swift test
```

`Tests/TableConverterCoreTests/Fixtures/python-reference.json`은 별도로 보존한 Python 코드에서 얻은 결과입니다. 원본 코드의 SHA-256과 한글 클립보드 예시 5개의 셀 병합, 셀 스타일, 문단, 글자 서식, 일반 텍스트를 기록했습니다. 비교 시 무작위 UUID는 제외합니다. 테스트 실행에는 Python이 필요하지 않습니다.

클립보드 테스트는 고유한 이름의 테스트용 클립보드를 사용하며 사용자의 일반 클립보드를 바꾸지 않습니다. 실제 한글·브라우저·네이버 카페 사이의 붙여넣기 검증은 별도로 수행해야 합니다.

전환 시 회귀 테스트 13개, 두 아키텍처의 Release 빌드, 앱 서명 검증이 통과했습니다. 이 Mac에서 앱 프로세스를 실행한 뒤 종료했습니다. 메뉴바 화면의 자동화 확인은 UI 도구 연결 시간 초과로 완료하지 못했습니다.

## 전환 시 유지한 범위

- 첫 번째 표 하나를 변환하며 표 밖의 본문은 옮기지 않습니다.
- 가로·세로 셀 병합, 배경색, 글자색, 굵게, 밑줄, 문단 단위 줄바꿈, 좌·중·우 정렬을 처리합니다.
- 대각선은 제외하고 알림으로 안내합니다.
- 기존과 같이 `pt` 단위 셀 너비는 `50%`, 테두리는 검은색 1px 실선으로 처리합니다.
- 글꼴과 크기는 나눔고딕·15 크기에 해당하는 네이버 클래스로 통일합니다.

언어 전환과 동작 개선을 구분하기 위해 기존 변환 규칙을 유지했습니다. 문자열로 HTML을 재구성할 때 특수문자가 태그로 해석되지 않도록 이스케이프하며, 실패하거나 변환 중 클립보드가 바뀌면 원본을 덮어쓰지 않습니다.

## 기존 Python 버전

기존 Python 프로젝트는 `/Users/jeonggeungyu/PythonProjects/phronesis_pyo/`에 보관합니다. 그 폴더의 `.command`와 패키지 생성 스크립트는 Python 버전용으로 복원했습니다.

현재 폴더의 `.command`와 패키지 생성 스크립트는 이 폴더의 Swift 앱을 빌드·실행합니다. 기존 위치에서 만든 Swift 빌드 캐시는 `.build/previous-location/`에 보존하고, 새 위치의 테스트와 앱 빌드는 새 캐시로 검증합니다.

SwiftSoup의 라이선스는 `THIRD_PARTY_NOTICES.txt`에 포함되어 있습니다.
