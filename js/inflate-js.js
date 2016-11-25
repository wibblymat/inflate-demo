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
'use strict';

class Tree {
  constructor() {
    this.left = null;
    this.right = null;
    this.value = null;
  }

  print(prior = '') {
    if (this.value !== null) {
      console.log(prior + ':', this.value);
    }
    if (this.left !== null) {
      this.left.print(prior + '0');
    }
    if (this.right !== null) {
      this.right.print(prior + '1');
    }
  }
}

const huffmanTreeFromLengths = function(lengths) {
  const counts = [];
  const nextCode = [];
  let highest = 0;
  for (let i = 0; i < lengths.length; i++) {
    highest = Math.max(highest, lengths[i]);
    counts[lengths[i]] = (counts[lengths[i]] || 0) + 1;
  }

  var code = 0;
  counts[0] = 0;

  for (let bits = 1; bits <= highest; bits++) {
    counts[bits] = counts[bits] || 0;
    code = (code + counts[bits - 1]) << 1;
    nextCode[bits] = code;
  }

  var tree = new Tree();

  for (let n = 0; n < lengths.length; n++) {
    let len = lengths[n];
    if (len !== 0) {
      const code = nextCode[len];
      let node = tree;
      nextCode[len]++;
      for (let i = 1; i <= len; i++) {
        if (code & (1 << (len - i))) {
          node.right = node.right || new Tree();
          node = node.right;
        } else {
          node.left = node.left || new Tree();
          node = node.left;
        }
      }
      node.value = n;
    }
  }

  return tree;
};

const CL_ORDER =
    [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
const BUFFER_SIZE = 32768;

class InflateJS {
  constructor(input) {
    this.input = input;
    this.pos = 0;

    this.complete = false;
    this.output = new Uint8Array(BUFFER_SIZE);
    this.currentBits = 0;
    this.bitsLeft = 0;
    this.writePos = 0;

    this.block = {
      type: null,
      final: false,
      lengthTree: null,
      distTree: null,
      length: 0 // For uncompressed blocks
    };

    const cmf = this.readInputByte();
    const method = cmf & 0xF;
    // const info = cmf >> 4;
    if (method !== 8) {
      throw new Error(`Unsupported compression method ${method}`);
    }

    const flags = this.readInputByte();
    // the fcheck value is just here to make sure that the (cmf * 256) + flags
    // value comes out as a multiple of 31. We don't actually need to use it.
    // const fcheck = flags & 0x1F;
    const fdict = (flags & 0x20) === 0x20;
    // flevel not needed for decompression, ignore.
    // const flevel = flags >> 6;

    if ((256 * cmf + flags) % 31 !== 0) {
      throw new Error('Invalid flag check');
    }

    if (fdict) {
      throw new Error('Pre-defined dictionaries not yet supported');
    }

    this.initBlock();
  }

  readInputByte() {
    return this.input[this.pos++];
  }

  readBits(count) {
    // bytes go to bits like:
    //  byte num      0       1
    //           |00000000|00000000|
    //  bit num   76543210 FEDBCA98
    var value = this.currentBits;
    while (count > this.bitsLeft) {
      value |= (this.readInputByte() << this.bitsLeft);
      this.bitsLeft += 8;
    }

    var result = value;
    result &= ((1 << count) - 1);

    this.currentBits = value >> count;
    this.bitsLeft -= count;

    return result;
  }

  initBlock() {
    if (this.complete) {
      throw new Error('Cannot read from completed stream');
    }

    this.block.final = this.readBits(1);
    this.block.type = this.readBits(2);

    var i;

    // I'll be honest - only block type 2 has actually been tested

    if (this.block.type === 3) {
      throw new Error('Invalid block compression type');
    } else if (this.block.type === 0) { // uncompressed
      this.bitsLeft = 0;
      this.currentBits = 0;
      var len = (this.readInputByte() << 8) | this.readInputByte();
      var nlen = (this.readInputByte() << 8) | this.readInputByte();
      if (len !== (-nlen + 1)) {
        throw new Error('Uncompressed block length encoding error');
      }
      this.block.length = len;
    } else if (this.block.type === 2) { // Huffman coding - read in dynamic codes
      var hlit = this.readBits(5); // Number of literal codes - 257
      var hdist = this.readBits(5); // Number of distance codes - 1
      var hclen = this.readBits(4); // Number of code length codes - 4
      // Code Length codes come in a particular order:
      var codeLengths =
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      for (i = 0; i < hclen + 4; i++) {
        codeLengths[CL_ORDER[i]] = this.readBits(3);
      }
      var codeTree = huffmanTreeFromLengths(codeLengths);

      var lens = [];
      i = 0;
      while (i < hlit + hdist + 258) {
        var code = this.readCode(codeTree);
        if (code <= 15) {
          lens[i++] = code;
        } else {
          var repeat = 0;
          var rcode = 0;
          if (code === 16) {
            repeat = this.readBits(2) + 3;
            rcode = lens[i - 1];
          } else if (code === 17) {
            repeat = this.readBits(3) + 3;
          } else if (code === 18) {
            repeat = this.readBits(7) + 11;
          }
          for (var j = 0; j < repeat; j++) {
            lens[i++] = rcode;
          }
        }
      }

      this.block.lengthTree = huffmanTreeFromLengths(lens.slice(0, hlit + 257));
      this.block.distTree = huffmanTreeFromLengths(lens.slice(hlit + 257));
    } else { // Huffman coding - fixed codes
      var lengthLens = [];
      var distLens = [];
      var l = 0;
      while (l < 144) {
        lengthLens[l++] = 8;
      }
      while (l < 256) {
        lengthLens[l++] = 9;
      }
      while (l < 280) {
        lengthLens[l++] = 7;
      }
      while (l < 288) {
        lengthLens[l++] = 8;
      }

      for (var d = 0; d < 32; d++) {
        distLens[d] = 5;
      }

      this.block.lengthTree = huffmanTreeFromLengths(lengthLens);
      this.block.distTree = huffmanTreeFromLengths(distLens);
    }
  }

  readValues() {
    if (this.block.type === 3) {
      throw new Error('Invalid block compression type');
    } else if (this.block.type === 0) { // uncompressed
      this.output[this.writePos++] = this.readInputByte();
      this.block.length--;
    } else { // Huffman coding
      const value = this.readCode(this.block.lengthTree);
      if (value < 256) {
        this.output[this.writePos++] = value;
      } else if (value === 256) {
        if (this.block.final) {
          this.complete = true;
          return;
        }
        this.initBlock();
        return this.readValues();
      } else { // otherwise (length = 257..285)
        let length = this.codeToLength(value);
        let distance = this.codeToDistance(this.readCode(this.block.distTree));
        var ptr = this.writePos - distance;
        while (ptr < 0) { // Don't just use % because JS uses signed mod
          ptr += BUFFER_SIZE;
        }
        for (let i = 0; i < length; i++) {
          this.output[this.writePos++ % BUFFER_SIZE] = this.output[ptr++ % BUFFER_SIZE];
        }
      }
    }
    this.writePos %= BUFFER_SIZE;
  }

  codeToLength(code) {
    if (code === 285) {
      return 258;
    }
    if (code < 265) {
      return code - 254;
    }

    const bits = (code - 261) >> 2;

    code -= 261 + (bits * 4);
    code <<= bits;
    code += (1 << (bits + 2)) + 3;
    code += this.readBits(bits);
    return code;
  }

  codeToDistance(code) {
    if (code < 4) {
      return code + 1;
    }

    let bits = Math.max((code >> 1) - 1, 0);
    let base = code % 2;
    let lower = ((2 + base) << bits) + 1;
    return lower + this.readBits(bits);
  }

  readCode(tree) {
    if (tree === null) {
      throw new Error('Ended up on a null tree');
    }

    if (tree.value !== null) {
      return tree.value;
    }

    if (this.readBits(1)) {
      return this.readCode(tree.right);
    }

    return this.readCode(tree.left);
  }

  read() {
    const decoder = new TextDecoder('utf-8');
    let readPos = 0;
    let outPos = 0;
    let outSize = BUFFER_SIZE;
    let output = new Uint8Array(outSize);

    this.readValues();

    while (!this.complete) {
      if (this.writePos < readPos) {
        for (let i = readPos; i < BUFFER_SIZE; i++) {
          output[outPos++] = this.output[i];
        }

        outSize += BUFFER_SIZE;
        let temp = new Uint8Array(outSize);
        temp.set(output);
        output = temp;

        for (let i = 0; i < this.writePos; i++) {
          output[outPos++] = this.output[i];
        }
      } else {
        for (let i = readPos; i < this.writePos; i++) {
          output[outPos++] = this.output[i];
        }
      }

      readPos = this.writePos;

      this.readValues();
    }

    return decoder.decode(output.slice(0, outPos));
  }
}

window.InflateJS = InflateJS;
