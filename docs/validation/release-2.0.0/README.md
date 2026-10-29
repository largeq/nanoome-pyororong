# 표로롱 2.0.0 첫 배포 검증

2026년 10월 29일(한국 시간), 사용자의 승인으로 **2.0.0(빌드 1)**을 [GitHub Release](https://github.com/largeq/nanoome-pyororong/releases/tag/v2.0.0)에 공개했다. 검증만을 위한 2.0.1은 만들지 않았다.

## 배포 파일

- 설치 파일: [Pyororong-2.0.0-1.zip](https://github.com/largeq/nanoome-pyororong/releases/download/v2.0.0/Pyororong-2.0.0-1.zip)
- 크기: **19,219,338바이트**
- SHA-256: `47f6a07e44bda8499040ad78f7bbcf57ebff37c5b6201574050080cd50d57274`
- 체크섬: [SHA256SUMS](https://github.com/largeq/nanoome-pyororong/releases/download/v2.0.0/SHA256SUMS)
- 태그: `v2.0.0`, 소스 커밋: `d8d3e4d9a3c97e4fd90781fdb9aa58b4b5b03108`
- 앱: `표로롱.app`, 실행 파일 `Pyororong`, Bundle ID `com.phronesis.pyororong`

Xcode에서 내보낸 공증 앱을 수정하거나 다시 서명하지 않고 `scripts/prepare-update.sh`로 ZIP과 appcast를 만들었다. Sparkle 개인 키는 Keychain 안에서만 사용했으며 소스·파일·환경 변수·로그로 내보내지 않았다. GitHub CLI 인증도 기존 Git 인증을 프로세스 메모리에서만 사용했다.

## 실제 검증 결과

1. 내보낸 앱의 `codesign --verify --deep --strict`가 통과했다. Developer ID Application 서명, 보안 타임스탬프와 hardened runtime을 확인했다.
2. `xcrun stapler validate`가 통과했고 `spctl --assess --type execute`는 **accepted / Notarized Developer ID**를 반환했다.
3. 앱과 Sparkle은 `arm64`·`x86_64`를 모두 포함하며, 앱의 두 아키텍처 모두 최소 OS 12.0이다. 번들 영상·라이선스·업데이트 설정도 검토한 소스와 일치했다.
4. 생성한 ZIP의 Ed25519 전자서명을 **실제 앱에 포함된 공개 키**로 별도 검증했다. ZIP을 다시 풀어도 실행 파일 바이트·프레임워크 서명·공증 티켓·Gatekeeper 승인과 Universal 구성이 보존됐다.
5. Release 초안의 커밋·한국어 안내·ZIP과 체크섬 이름·크기·업로드 상태·해시를 대조한 뒤 공개했다. 공개 ZIP과 체크섬을 **인증 없이 실제 다운로드**해 로컬 원본과 바이트 및 SHA-256이 일치함을 확인했다.
6. 다운로드 검증 후 생성된 appcast를 수정 없이 `main/updates/appcast.xml`에 게시했다. [운영 주소](https://raw.githubusercontent.com/largeq/nanoome-pyororong/main/updates/appcast.xml)는 인증 없이 HTTP 200이며 생성본과 바이트가 일치했다. 기존 이력을 보존하는 fast-forward push만 사용했다.
7. 실제 앱의 `UpdateController`와 Sparkle 2.10.1을 사용해 운영 주소를 조회했다. `SUSparkleErrorDomain / 1001`, 현재 버전 사유 `1`, 파싱한 최신 버전 **2.0.0(빌드 1)**, `hasUpdate=false`를 확인했다. HTTP 성공만으로 통과 판정하지 않았다.

운영 조회 검사는 고유한 임시 번들과 설정을 사용하고 자동 확인·다운로드를 껐다. `checkForUpdateInformation()`만 호출했으며 설치를 요청하지 않았다. 일반 클립보드가 보존되고 임시 파일·저장 설정이 정리된 것도 확인했다. 생성된 안내 파일의 사전 로컬 검사에서는 appcast 요청 1회, ZIP 요청 0회였다.

보조 검사의 최초 실행은 삭제된 UserDefaults 도메인이 `nil` 대신 빈 사전으로 반환되어 정리 확인에 실패했다. Sparkle 없이 같은 API 동작을 재현한 뒤 저장 키가 0개인지 확인하도록 검사 자체를 수정했다. 제품 코드와 최신 버전 판정 조건은 바꾸지 않았고, 같은 생성 안내 파일과 공개 운영 주소의 검사 모두 통과했다.

## 증거 자료

- [파일·서명·아키텍처 메타데이터](artifact.json)
- [공개 Release와 자산 정보](release.json)
- [비로그인 다운로드 결과](public-downloads.json)
- [운영 appcast HTTP 결과](public-feed-http.json)
- [실제 Sparkle 최신 버전 판정](production-feed.json)
- [서명·공증·ZIP 보존·공개 키 서명 검증 로그](checks.log)

실제 한글·네이버 붙여넣기는 사용자가 완료했다고 확인했다. 다른 Mac·구형 macOS 실행, VoiceOver와 지속 60fps 실측은 사용자 선택으로 이번 배포 검증에서 제외했다. 이전 공증 버전에서 새 버전으로 교체·재실행하는 검사는 실제 다음 업데이트를 준비할 때 수행한다.

## 같은 버전의 DMG 추가

2026년 10월 29일 사용자의 요청으로 같은 Release에 [Pyororong-2.0.0-1.dmg](https://github.com/largeq/nanoome-pyororong/releases/download/v2.0.0/Pyororong-2.0.0-1.dmg)와 [전용 체크섬](https://github.com/largeq/nanoome-pyororong/releases/download/v2.0.0/Pyororong-2.0.0-1.dmg.sha256)을 추가했다. 크기는 **19,195,392바이트**, SHA-256은 `3c8f7e4340105cc54008bb45b1007dbb866ac0c788e3e82ed973bbe8893042a4`다.

읽기 전용 UDZO 디스크 이미지에 기존 공증된 앱을 `ditto`로 복사하고, `/Applications`를 가리키는 **응용 프로그램** 링크를 넣었다. 앱이나 내부 프레임워크를 다시 서명하거나 수정하지 않았다. 이미 서명·공증·티켓 스테이플을 마친 앱을 DMG로 감싸고 DMG 자체의 서명·공증을 생략하는 [Apple DTS 안내](https://developer.apple.com/forums/thread/741219)를 따랐다. **DMG 컨테이너 자체는 서명·공증하지 않았으며**, 서명·공증·티켓과 Gatekeeper 승인 검사는 내부 앱을 대상으로 수행했다.

디스크 이미지 무결성 검사가 통과했고 읽기 전용으로 마운트해 앱의 파일·심볼릭 링크 78개 항목이 원본과 일치함을 확인했다. 내부 앱의 깊은 서명 검사, 공증 티켓, Gatekeeper 승인과 Intel·Apple Silicon 구성이 모두 통과했다. 검사가 끝나면 마운트를 해제했다.

공개 DMG와 체크섬을 인증 없이 실제 다운로드해 HTTP 200 응답과 로컬 원본의 바이트·해시 일치를 확인했다. 기존 ZIP과 `SHA256SUMS`의 자산 ID·크기·해시는 그대로이며 운영 appcast와 그 ZIP 전자서명도 변경하지 않았다. GitHub Release와 문서의 첫 설치 안내는 DMG 기준으로 갱신했다.

- [DMG 메타데이터](dmg-artifact.json)
- [무결성·내부 앱 검증 로그](dmg-checks.log)
- [공개 다운로드 결과](dmg-public-downloads.json)
- [DMG 추가 후 Release 자산과 기존 파일 보존 확인](dmg-release.json)
