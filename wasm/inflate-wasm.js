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

class InflateWasm {
  constructor(module, input) {
    let ptr = 0;

    this._memory = new WebAssembly.Memory({initial: 1});

    const imports = {
      env: {
        // Read up to size bytes into the buffer at buf
        readInput: (buf, size) => {
          const mem = new Uint8Array(this.memory.buffer, buf, size);
          const bytes = Math.min(size, input.length - ptr);
          mem.set(input.slice(ptr, ptr + bytes));
          ptr += bytes;
          return bytes;
        },
        error: addr => {
          const decoder = new TextDecoder('utf-8');
          let end = addr;
          const memory = new Uint8Array(this.memory.buffer);
          while (memory[end] !== 0) {
            end++;
          }
          throw new Error(decoder.decode(memory.slice(addr, end)));
        },
        memset: (a, b, c) => {
          const memory = new Uint8Array(this.memory.buffer);
          memory.fill(b, a, a + c);
          return a;
        },
        memory: this._memory
      }
    };

    this.instance = new WebAssembly.Instance(module, imports);
    this.instance.exports.init();
  }

  get memory() {
    return this.instance.exports.memory || this._memory;
  }

  read() {
    const BUFFER_SIZE = this.instance.exports.getBufferSize();
    let oPtr = this.instance.exports.getOutputBuffer();
    let currMem = this.memory;
    let buffer = new Uint8Array(currMem.buffer, oPtr, BUFFER_SIZE);

    const decoder = new TextDecoder('utf-8');
    let readPos = 0;
    let outPos = 0;
    let outSize = BUFFER_SIZE;
    let output = new Uint8Array(outSize);

    let writePos = this.instance.exports.readValues();

    while (!this.instance.exports.isComplete()) {
      if (this.memory !== currMem) {
        currMem = this.memory;
        buffer = new Uint8Array(currMem.buffer, oPtr, BUFFER_SIZE);
      }
      if (writePos < readPos) {
        output.set(buffer.slice(readPos, BUFFER_SIZE), outPos);
        outPos += (BUFFER_SIZE - readPos);

        outSize += BUFFER_SIZE;
        let temp = new Uint8Array(outSize);
        temp.set(output);
        output = temp;

        readPos = 0;
      }

      output.set(buffer.slice(readPos, writePos), outPos);
      outPos += (writePos - readPos);

      readPos = writePos;

      writePos = this.instance.exports.readValues();
    }

    if (writePos < readPos) {
      output.set(buffer.slice(readPos, BUFFER_SIZE), outPos);
      outPos += (BUFFER_SIZE - readPos);

      outSize += BUFFER_SIZE;
      let temp = new Uint8Array(outSize);
      temp.set(output);
      output = temp;

      readPos = 0;
    }

    output.set(buffer.slice(readPos, writePos), outPos);
    outPos += (writePos - readPos);


    return decoder.decode(output.slice(0, outPos));
  }
}

window.InflateWasm = InflateWasm;
