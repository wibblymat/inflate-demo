#!/bin/bash
# Copyright 2016 Google Inc. All Rights Reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build 1: clang > llvm > s2wasm > wasm-as
~/llvm/build/bin/clang -emit-llvm -DWASM --target=wasm32 -S inflate.c
~/llvm/build/bin/llc inflate.ll -march=wasm32
~/binaryen/build/bin/s2wasm -o inflate.wast inflate.s
~/binaryen/build/bin/wasm-opt -O3 -o inflate.wast inflate.wast
~/binaryen/build/bin/wasm-as -o inflate.wasm inflate.wast
rm -f inflate.ll inflate.wast inflate.s

# Set up emscripten
# ~/emsdk_portable/emsdk activate sdk-incoming-64bit
source ~/emsdk_portable/emsdk_env.sh

# Build 2: emscripten > asm.js > wasm
# Uses the 'incoming' branch of portable emscripten
python `which emcc` \
  -s "BINARYEN_METHOD='native-wasm'" \
  -s MAIN_MODULE=2 \
  -s WASM=1 \
  -s EXPORT_NAME="'InflateEmscriptenModule'" \
  -s MODULARIZE=1 \
  -s EXPORTED_FUNCTIONS="['_getBufferSize','_getOutputBuffer','_isComplete','_readValues','_init']" \
  -DEMSCRIPTEN \
  -O3 \
  inflate.c -o \
  inflate-emscripten.js
rm inflate-emscripten.wast inflate-emscripten.asm.js

# Build 3: Hand made wast > wasm
~/binaryen/build/bin/wasm-opt -O3 -o inflate-manual-opt.wast inflate-manual.wast
~/binaryen/build/bin/wasm-as -o inflate-manual.wasm inflate-manual-opt.wast
rm inflate-manual-opt.wast
