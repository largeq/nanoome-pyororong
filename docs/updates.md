# 표로롱 업데이트 확인과 배포

## 첫 배포 상태

2026년 10월 29일 **2.0.0(빌드 1)**의 [첫 GitHub Release](https://github.com/largeq/nanoome-pyororong/releases/tag/v2.0.0)를 게시했다. 배포용 앱은 Apple Silicon·Intel Universal 구조, Developer ID Application 서명, hardened runtime, Apple 공증과 티켓 스테이플, Gatekeeper 검증을 통과했다. 첫 포장의 DMG와 `Pyororong-2.0.0-1.dmg.sha256`은 로그인 없이 HTTP 200으로 내려받아 원본 일치를 확인했다.

운영용 `updates/appcast.xml`을 기본 브랜치 `main`에 게시했다. 공개 주소의 HTTP 200 응답과 생성본 일치를 확인했으며, 실제 앱의 `UpdateController`와 Sparkle이 2.0.0(빌드 1)을 최신 버전으로 판정했다. 자세한 결과와 배포 파일 해시는 [배포 검증 기록](validation/release-2.0.0/README.md)에 있다.

다른 Mac·구형 macOS 실행, VoiceOver 음성 읽기와 지속 60fps 실측은 사용자 선택으로 이번 배포 검증에서 제외했다. 첫 배포에는 이전 공증 버전이 없으므로 다운로드·교체·재실행을 거치는 실제 업데이트 검증은 다음 업데이트 때 수행한다.

## 처음 설치할 때

설치 파일은 [r2 DMG](https://github.com/largeq/nanoome-pyororong/releases/download/v2.0.0/Pyororong-2.0.0-1-r2.dmg)로 제공한다. 흰 바탕의 설치창에서 왼쪽 `표로롱.app`을 오른쪽 **응용 프로그램** 폴더로 복사한다. 본문 상단에 별도 브랜드 표시는 두지 않고, **표로롱을 응용 프로그램 폴더로 드래그하세요.**라는 한 줄 안내를 사용한다. [r2 DMG 체크섬](https://github.com/largeq/nanoome-pyororong/releases/download/v2.0.0/Pyororong-2.0.0-1-r2.dmg.sha256)은 별도 파일로 제공한다.

r2는 설치창 디자인을 바꾼 재포장 번호이며 앱 버전·빌드 번호는 2.0.0(1)로 유지한다. 기존 URL의 서명 대상 바이트를 덮어쓰지 않고 새 파일명으로 구분한다. 새 포장의 검증 범위와 실제 결과는 [설치창 변경 기록](validation/dmg-layout-2026-10-29/README.md)에 별도로 남긴다.

직접 설치와 Sparkle 업데이트는 같은 DMG를 사용한다. 운영용 `appcast.xml`에는 DMG의 주소·크기와 해당 파일의 Ed25519 전자서명을 넣는다. Release에는 DMG와 그 체크섬을 남기며 ZIP과 ZIP용 `SHA256SUMS`는 제공하지 않는다. DMG와 그 안의 앱에 대한 검증 결과는 [배포 검증 기록](validation/release-2.0.0/README.md)에 구분해 기록한다.

## 앱에서 보이는 동작

메뉴의 **업데이트 확인…**은 **표로롱에 관하여** 바로 위에 있다. **설정…**(⌘,) 창의 **업데이트 → 자동으로 업데이트 확인**은 처음에는 켜져 있다. 사용자가 끄면 그 선택을 유지하며, 자동 확인을 꺼도 수동 확인은 가능하다. 설정의 변경은 **저장**해야 적용하고 **취소**·창 닫기는 적용하지 않는다.

자동 확인은 앱이 실행 중일 때 하루 간격으로 수행한다. 새 버전이 없거나 일시적으로 연결할 수 없는 경우 자동 확인은 작업을 방해하는 오류 창을 띄우지 않는다. 사용자가 직접 확인한 경우에는 최신 버전·새 버전·확인 실패를 구별해 안내한다. 자동 다운로드·자동 설치는 비활성화했으며 이를 켜는 선택지도 제공하지 않는다. 다운로드와 설치는 사용자가 설치를 선택한 경우에만 진행한다. 표 변환이 진행 중이면 앱 교체와 재실행을 변환 완료 뒤로 미룬다.

확인·다운로드·사용자가 선택한 설치는 [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1)이 담당한다. 버전 비교는 앱의 `CFBundleVersion`(빌드 번호)을 기준으로 한다. 표 변환 엔진은 업데이트 기능과 별개다.

## 배포 구성

- 앱 ID: `com.phronesis.pyororong`
- 업데이트 안내 파일: `https://raw.githubusercontent.com/largeq/nanoome-pyororong/main/updates/appcast.xml`
- 설치 파일: 공식 저장소의 GitHub Releases
- Sparkle Ed25519 개인 키: 이 Mac의 로그인 Keychain, 계정 이름 `com.phronesis.pyororong`
- 공개 키: `App/Info.plist`의 `SUPublicEDKey`. 공개 키는 소스에 포함해도 되지만 개인 키는 포함하거나 출력하지 않는다.

안내 파일은 다운로드할 버전·변경 사항·설치 파일 주소와 전자서명을 담는다. GitHub에 소스를 올리는 것만으로 업데이트가 배포되는 것은 아니다. 실제 설치 파일을 게시하고 안내 파일도 갱신해야 한다.

## 로컬 빌드와 배포 빌드의 구별

`scripts/build-app.sh`는 개발 중 실행을 위한 **로컬 개발 빌드**다. 서명은 Xcode 설정에 따라 개발용 또는 ad-hoc이며, Sparkle을 로컬에서 불러올 수 있도록 이 명령에서만 hardened runtime을 끈다. Xcode 프로젝트의 배포 설정은 hardened runtime을 유지한다. GitHub 배포용 앱은 별도로 Developer ID 서명과 Apple 공증을 거쳐 준비한다.

정식 업데이트에는 Apple Silicon·Intel을 모두 포함한 Universal 앱, Developer ID Application 서명, Apple 공증과 스테이플된 공증 티켓이 필요하다. 첫 배포용 2.0.0(빌드 1) 앱은 이 검증을 마쳤으며, 설치 파일을 먼저 게시한 뒤 실제 파일을 가리키는 운영용 안내 파일도 게시했다. 공개된 공증 앱 사이의 실제 버전 교체는 다음 업데이트 때 검증하며, 존재하지 않는 배포 파일을 가리키는 가상 안내를 만들지 않는다.

## 배포 파일 준비

DMG 제작용 도구는 프로젝트 루트에서 한 번 준비한다. 이 Python 환경은 개발자의 배포 파일 생성에만 사용하며, 사용자가 표로롱을 설치하거나 실행할 때는 Python이 필요하지 않다.

```sh
python3 -m venv .build/dmg-tools
.build/dmg-tools/bin/python -m pip install -r scripts/requirements-dmg.txt
```

1. 새 버전과 빌드 번호를 정한다. 이 프로젝트의 준비 스크립트는 숫자와 점으로 된 번호를 사용하며, 이전 안내 파일에 있는 모든 버전과 빌드 번호보다 각각 커야 한다. 예를 들어 `2.0.0 (1)` 다음에는 `2.1.0 (2)`를 사용할 수 있다.
2. Xcode의 **Product → Archive → Distribute App → Direct Distribution** 절차로 배포용 앱을 만든다. 배포용 Developer ID 인증서와 팀을 선택하고 hardened runtime을 유지한다. 명령으로 Archive를 만들 때도 로컬 스크립트의 `ENABLE_HARDENED_RUNTIME=NO`를 사용하지 않는다.
3. Apple 공증을 완료하고 내보낸 `.app`에 티켓을 스테이플한다. `xcrun stapler validate`와 `spctl --assess --type execute`가 통과하는 앱을 사용한다.
4. 한국어 변경 사항을 Markdown 파일로 준비한다.
5. 이전 배포가 있으면 현재 공개 안내 파일의 최신 사본을 준비한다. 저장소의 `updates/appcast.xml`이 최신임을 확인하거나 네 번째 인자로 최신 파일을 지정한다.

예를 들어 공증을 마친 앱이 `.build/distribution/표로롱.app`이고 변경 사항이 `.build/release-notes/2.1.0.md`라면 다음과 같이 실행한다. 앱 안의 버전·빌드 번호도 `2.1.0 (2)`여야 한다.

```sh
bash scripts/prepare-update.sh \
  '.build/distribution/표로롱.app' \
  '.build/release-notes/2.1.0.md' \
  '.build/updates/2.1.0'
```

이전 안내 파일을 명시하려면 마지막에 경로를 덧붙인다.

```sh
bash scripts/prepare-update.sh \
  '.build/distribution/표로롱.app' \
  '.build/release-notes/2.1.0.md' \
  '.build/updates/2.1.0' \
  '.build/current-published-appcast.xml'
```

스크립트는 Bundle ID·공개 키·버전·서명·Universal 구조·공증을 검사한다. ad-hoc 앱, 잘못된 키, 증가하지 않은 버전은 출력 파일을 만들기 전에 거부한다. DMG 생성은 `scripts/build-dmg.sh`와 `scripts/dmg-settings.py`를 공통으로 사용해 흰 바탕·한 줄 안내·왼쪽 앱과 오른쪽 응용 프로그램 폴더 배치를 재현한다. 정식 배경은 `Assets/DMG/background.png`와 `background@2x.png`이며, 개발 중 배경을 수정할 때는 `swift scripts/render-dmg-background.swift Assets/DMG`로 다시 만든다. 검사를 통과하면 다음 파일을 만든다.

- `Pyororong-2.1.0-2.dmg`: 앱과 응용 프로그램 폴더 링크를 포함한 읽기 전용 배포 디스크 이미지. 앱 내부의 심볼릭 링크를 보존한다.
- `Pyororong-2.1.0-2.dmg.sha256`: DMG의 SHA-256 체크섬.
- `appcast.xml`: 변경 사항과 설치 파일의 전자서명을 포함한 안내 파일.
- `Pyororong-2.1.0-2.md`: 변경 사항 사본. 안내 파일 안에도 내용을 포함하므로 별도 공개 주소는 필요하지 않다.

Sparkle의 `generate_appcast --account com.phronesis.pyororong`이 Keychain의 키를 사용해 서명한다. 개인 키를 파일이나 환경 변수로 내보내지 않는다. 설치 파일 주소는 해당 버전의 Release에 고정하며, 이 예시에서는 다음 주소를 사용한다.

```text
https://github.com/largeq/nanoome-pyororong/releases/download/v2.1.0/Pyororong-2.1.0-2.dmg
```

준비 스크립트는 파일을 생성할 뿐 GitHub에 게시하지 않는다.

## 게시 순서와 완료 확인

1. GitHub에서 `v2.1.0` 태그의 Release를 만들고 `Pyororong-2.1.0-2.dmg`, 해당 `.dmg.sha256`과 변경 사항을 게시한다. 예시 번호는 실제 준비한 앱과 일치하도록 바꾼다.
2. 로그인이 필요 없는 브라우저에서도 정확한 설치 파일 주소로 다운로드할 수 있는지 확인한다.
3. 생성된 `appcast.xml`을 저장소의 `updates/appcast.xml`로 복사해 기본 브랜치에 게시한다. 새 파일을 가리키는 안내를 설치 파일보다 먼저 게시하지 않는다. 생성된 안내의 버전·설치 파일 주소·전자서명을 임의로 바꾸거나, 서명한 설치 파일을 다시 수정하지 않는다.
4. 앱에 설정된 안내 파일 주소가 HTTP 200으로 열리는지 확인한다.
5. 두 번째 배포부터는 이전 **공증된** 표로롱에서 수동 확인을 실행한다. 새 버전과 변경 사항을 확인하고 설치를 선택해 정상 교체·재실행되는지 검사한다. 단축키·자동 확인 선택과 클립보드가 보존되는지도 확인한다. 첫 배포는 이전 공증 버전이 없으므로 이 검사를 다음 업데이트로 미룬다.
6. 자동 확인 켬·끔과 수동 확인을 각각 시험한다. 자동 확인을 껐을 때 주기 확인이 멈추고, 수동 확인은 계속 가능해야 한다. 사용자 선택 전에는 앱 파일을 내려받거나 교체하지 않아야 한다.

새 버전 발견과 실제 교체를 시험하기 전에는 공개 업데이트 기능이 검증 완료되었다고 안내하지 않는다. 새 버전이 없다는 결과와 네트워크·안내 파일 오류도 구분해 확인한다.

공식 참고: [Sparkle 설치·배포](https://sparkle-project.org/documentation/), [설정](https://sparkle-project.org/documentation/customization/), [배포 안내 파일 생성](https://sparkle-project.org/documentation/publishing/).
