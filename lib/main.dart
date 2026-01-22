name: Final Polish Build
on: [push, workflow_dispatch]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Java Setup
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Flutter Setup
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.1'
          channel: 'stable'

      - name: 안드로이드 설정 및 권한 복구
        run: |
          # 기본 안드로이드 구조가 없으면 생성하되 기존 리소스는 유지
          if [ ! -d "android" ]; then
            flutter create . --platforms android --org com.example
          fi
          
          # AndroidManifest.xml에 근처 기기(블루투스) 권한 주입
          sed -i '/<application/i \    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />\n    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />' android/app/src/main/AndroidManifest.xml
          
          flutter pub get
          # 아이콘과 스플래시 화면 재생성
          flutter pub run flutter_launcher_icons:main || true
          flutter pub run flutter_native_splash:create || true
          
          flutter build apk --debug --no-tree-shake-icons

      - name: APK 추출
        uses: actions/upload-artifact@v4
        with:
          name: over-the-bike-final
          path: "build/app/outputs/flutter-apk/app-debug.apk"
