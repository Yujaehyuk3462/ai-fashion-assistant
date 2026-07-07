# AI Fashion Assistant

Gemini API 기반의 AI 옷장 & 가상 피팅 Flutter 앱입니다.
내 옷을 등록해두면 AI가 속성을 자동으로 분석하고, 체형 정보와 비교해 핏을 예측하며, 실제로 입어본 것 같은 가상 피팅 이미지를 생성해줍니다.

## 소개

옷장 정리부터 코디 조합, 착용 시뮬레이션까지 한 곳에서 해결하는 것을 목표로 하는 개인 패션 도우미 앱입니다.

- 옷 사진 한 장만 등록하면 카테고리·색상·스타일·패턴을 AI가 자동으로 추출
- 체형 프로필과 옷 치수를 비교해 타이트/정핏/오버핏 여부를 미리 확인
- Gemini API로 사용자 사진에 옷을 합성한 가상 피팅 이미지 생성
- 옷장 아이템을 조합해 나만의 코디보드 구성

## 주요 기능

### AI 옷장
옷을 촬영/업로드하면 배경 제거 후 AI가 카테고리, 색상, 스타일, 패턴 등 속성을 자동으로 추출해 Firestore에 캐싱합니다. 이후 분석 시에는 이미지를 재전송하지 않고 저장된 속성 텍스트를 활용해 응답 속도를 높였습니다.

### 사이즈 입력 & 예상 핏 예측
사이즈표를 캡처하면 OCR로 치수를 자동 인식해 입력하거나, 직접 치수를 입력할 수 있습니다. 저장된 체형 프로필과 옷 치수를 규칙 기반으로 비교해 타이트/정핏/오버핏 뱃지를 옷장 카드에 표시합니다.

### AI 가상 피팅룸
사용자 사진과 선택한 옷들을 Gemini API에 전달해 실제로 착용한 것 같은 합성 이미지를 생성합니다.

### 코디보드
아우터, 상의, 하의, 액세서리 등 슬롯 단위로 옷장 아이템을 배치해 코디를 조합하고 저장할 수 있습니다.

### 체형 프로필
퍼스널 컬러, 체형, 선호 스타일 등을 입력해 핏 예측과 코디 추천의 기준으로 활용합니다.

### 계정 & 저장
Firebase Authentication(익명 로그인), Firestore, Firebase Storage를 통해 옷장 데이터와 이미지를 안전하게 저장합니다.

## 스크린샷

| 홈 | 옷장 | 가상 피팅룸 |
| :---: | :---: | :---: |
| ![홈 화면](assets/screenshots/home.png) | ![옷장 화면](assets/screenshots/wardrobe.png) | ![가상 피팅룸](assets/screenshots/fitting_room.png) |

| 코디보드 | 체형 프로필 | 설정 |
| :---: | :---: | :---: |
| ![코디보드](assets/screenshots/coord_board.png) | ![체형 프로필](assets/screenshots/body_profile.png) | ![설정 화면](assets/screenshots/settings.png) |

## 기술 스택

- **Framework**: Flutter
- **AI**: Google Gemini API (`google_generative_ai`)
- **Backend**: Firebase (Authentication, Firestore, Storage, App Check)
- **이미지 처리**: `image_picker`, `image_cropper`, `image_background_remover`, `cached_network_image`

## 시작하기

```bash
flutter pub get
flutter run
```

Gemini API 키 등 민감한 값은 `lib/config/` 하위의 환경 설정 파일에 별도로 관리합니다.
