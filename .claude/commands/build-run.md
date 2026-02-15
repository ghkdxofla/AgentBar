Build and relaunch CCUsageBar app.

1. Build the project:
```
xcodebuild build -project CCUsageBar.xcodeproj -scheme CCUsageBar -configuration Debug -derivedDataPath build -quiet
```

2. If the build succeeds, kill the existing process and launch the new build:
```
pkill -x CCUsageBar; sleep 1; open build/Build/Products/Debug/CCUsageBar.app
```

3. Report whether the build succeeded or failed. If it failed, show the error output.
