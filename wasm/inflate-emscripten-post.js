/* global InflateEmscriptenModule */

class InflateEmscripten {
  constructor(wasm, input) {
    let ptr = 0;
    this.module = new InflateEmscriptenModule({
      wasmBinary: wasm,
      // Read up to size bytes into the buffer at buf
      _readInput: (buf, size) => {
        const mem = new Uint8Array(this.memory.buffer, buf, size);
        const bytes = Math.min(size, input.length - ptr);
        mem.set(input.slice(ptr, ptr + bytes));
        ptr += bytes;
        return bytes;
      },
      _error: addr => {
        const decoder = new TextDecoder('utf-8');
        let end = addr;
        const memory = new Uint8Array(this.memory.buffer);
        while (memory[end] !== 0) {
          end++;
        }
        throw new Error(decoder.decode(memory.slice(addr, end)));
      },
      _memset: (a, b, c) => {
        const memory = new Uint8Array(this.memory.buffer);
        memory.fill(b, a, a + c);
        return a;
      }
    });
    this.module._init();
  }

  get memory() {
    return this.module.wasmMemory;
  }

  read() {
    const BUFFER_SIZE = this.module._getBufferSize();
    let oPtr = this.module._getOutputBuffer();
    let currMem = this.memory;
    let buffer = new Uint8Array(currMem.buffer, oPtr, BUFFER_SIZE);

    const decoder = new TextDecoder('utf-8');
    let readPos = 0;
    let outPos = 0;
    let outSize = BUFFER_SIZE;
    let output = new Uint8Array(outSize);

    let writePos = this.module._readValues();

    while (!this.module._isComplete()) {
      if (this.memory !== currMem) {
        currMem = this.memory;
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

      writePos = this.module._readValues();
    }

    return decoder.decode(output.slice(0, outPos));
  }
}

window.InflateEmscripten = InflateEmscripten;
