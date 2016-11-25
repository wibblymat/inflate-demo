/*
  Copyright 2016 Google Inc. All Rights Reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
      http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/* global WebAssembly */

const modulePromise = fetch('wasm/inflate.wasm')
  .then(resp => resp.arrayBuffer())
  .then(buf => WebAssembly.compile(buf));

class InflateWasm {
  constructor(module, input) {
    let ptr = 0;
    const imports = {
      env: {
        // Read up to size bytes into the buffer at buf
        readInput: (buf, size) => {
          const mem = new Uint8Array(this.instance.exports.memory.buffer, buf, size);
          const bytes = Math.min(size, input.length - ptr);
          mem.set(input.slice(ptr, ptr + bytes));
          ptr += bytes;
          return bytes;
        },
        error: addr => {
          const decoder = new TextDecoder('utf-8');
          let end = addr;
          const memory = new Uint8Array(this.instance.exports.memory.buffer);
          while (memory[end] !== 0) {
            end++;
          }
          console.log(decoder.decode(memory.slice(addr, end)));
        },
        memset: (a, b, c) => {
          const memory = new Uint8Array(this.instance.exports.memory.buffer);
          memory.fill(b, a, a + c);
          return a;
        }
      }
    };

    this.instance = new WebAssembly.Instance(module, imports);
    this.instance.exports.init();
  }

  read() {
    const BUFFER_SIZE = this.instance.exports.getBufferSize();
    let oPtr = this.instance.exports.getOutputBuffer();
    let currMem = this.instance.exports.memory;
    let buffer = new Uint8Array(currMem.buffer, oPtr, BUFFER_SIZE);

    const decoder = new TextDecoder('utf-8');
    let readPos = 0;
    let outPos = 0;
    let outSize = BUFFER_SIZE;
    let output = new Uint8Array(outSize);

    let writePos = this.instance.exports.readValues();

    while (!this.instance.exports.isComplete()) {
      if (this.instance.exports.memory !== currMem) {
        currMem = this.instance.exports.memory;
        buffer = new Uint8Array(currMem.buffer, oPtr, BUFFER_SIZE);
      }
      if (writePos < readPos) {
        for (let i = readPos; i < BUFFER_SIZE; i++) {
          output[outPos++] = buffer[i];
        }

        outSize += BUFFER_SIZE;
        let temp = new Uint8Array(outSize);
        temp.set(output);
        output = temp;

        for (let i = 0; i < writePos; i++) {
          output[outPos++] = buffer[i];
        }
      } else {
        for (let i = readPos; i < writePos; i++) {
          output[outPos++] = buffer[i];
        }
      }

      readPos = writePos;

      writePos = this.instance.exports.readValues();
    }

    return decoder.decode(output.slice(0, outPos));
  }
}

const getWASMInflate = function(input) {
  return modulePromise.then(module => {
    return new InflateWasm(module, input);
  });
};

window.getWASMInflate = getWASMInflate;
