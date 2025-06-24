#!/bin/bash

echo "Fixing k-NN formatting..."
cd /home/junqiu/k-NN
./gradlew spotlessApply
echo "Formatting fixed!"