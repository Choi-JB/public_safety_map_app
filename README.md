# Public Safety Map — Flutter App

웹(`public_safety_map_web`)과 동일 백엔드(`:4100`)를 사용하는 모바일 클라이언트입니다.

## 포함 범위 (현재 BE 기준)

- 로그인 / 회원가입 / 로그아웃 / 비밀번호 변경
- 지도: 격자 · 제보 · 도시정보 · 인프라 · 사고다발
- 제보 작성 (이미지 마스킹 업로드 포함)
- 마이페이지 (요약, 내 제보, 내 피드백 조회)

## 제외 (BE/제품 범위 밖)

- 피드백 **작성** (`/feedbacks` 미구현)
- 푸시 (`/devices` 미구현)
- 관리자 (`/admin` — 웹 권장)

## 실행

백엔드가 `4100`에서 떠 있어야 합니다.

```bash
cd D:\0727\public_safety_map_app

# Android 에뮬레이터 (기본 API host = 10.0.2.2)
flutter run

# iOS 시뮬레이터 / 데스크톱
flutter run --dart-define=API_BASE_URL=http://localhost:4100

# 실기기 (PC LAN IP로 교체)
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:4100
```

## 구성

```
lib/
  core/config, network, theme
  data/models, repositories
  features/auth, map, mypage, report
  providers/
  main.dart
```

## 지도

MVP는 **OpenStreetMap + flutter_map** 입니다.  
카카오 맵 SDK 연동은 키 설정 후 교체 가능하며, API 레이어(격자/제보 등)는 그대로 재사용합니다.

## BE CORS

모바일 앱 origin은 Next와 다릅니다. 로컬 개발 중 API 호출이 CORS로 막히면 백엔드 `cors` origin 목록을 확인하세요.  
(네이티브 앱은 CORS 영향이 없고, 주로 WebView/데스크톱에서 이슈가 납니다.)
