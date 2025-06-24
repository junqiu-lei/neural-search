#!/bin/bash

echo "Building k-NN plugin with debug logging..."
cd /home/junqiu/k-NN
./gradlew clean
./gradlew build -x test -x integTest

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Plugin ZIP location:"
    ls -la build/distributions/*.zip
else
    echo "Build failed!"
    exit 1
fi