rm -rf build
flutter clean
flutter build apk --obfuscate --split-debug-info=HLQ_Struggle --target-platform android-arm,android-arm64,android-x64 --split-per-abi

# flutter build apk --target-platform android-arm,android-arm64,android-x64 --no-shrink

#doc
#flutter build apk --split-per-abi

#flutter clean
#flutter build appbundle --target-platform android-arm,android-arm64
