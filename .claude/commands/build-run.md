Build and relaunch AgentBar app.

1. Build the project:
```
xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet
```

2. If the build succeeds, kill the existing process and launch the new build:
```
pkill -x AgentBar; sleep 1; open build/Build/Products/Debug/AgentBar.app
```

3. Report whether the build succeeded or failed. If it failed, show the error output.
