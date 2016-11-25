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
#include "malloc.c"
typedef char bool;
typedef unsigned char byte;
#define true (bool)1;
#define false (bool)0;

byte readInputByte();
void error(char*);

int CL_ORDER[] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
int BUFFER_SIZE = 32768;

typedef struct Tree {
  struct Tree* left;
  struct Tree* right;
  int value;
} Tree;

bool complete = false;
byte* output;
int currentBits = 0;
int bitsLeft = 0;
int writePos = 0;

int blockType = 0;
bool blockFinal = false;
Tree* blockLengthTree = NULL;
Tree* blockDistTree = NULL;
int blockLength = 0; // For uncompressed blocks

Tree* newTree() {
  Tree* tree = (Tree*)malloc(sizeof(Tree));
  tree->value = -1;
  tree->left = NULL;
  tree->right = NULL;
  return tree;
}

void freeTree(Tree* tree) {
  if (tree->left != NULL) {
    freeTree(tree->left);
  }
  if (tree->right != NULL) {
    freeTree(tree->right);
  }
  free(tree);
}

int max(int a, int b) {
  return (a<b)?b:a;
}

Tree* huffmanTreeFromLengths(int size, int lengths[]) {
  int counts[288]; // 288 is the maximum, some may be unused
  int nextCode[16];
  int highest = 0;

  for (int i = 0; i < 288; i++) {
    counts[i] = 0;
  }

  for (int i = 0; i < size; i++) {
    highest = max(highest, lengths[i]);
    counts[lengths[i]]++;
  }

  int code = 0;
  counts[0] = 0;

  for (int bits = 1; bits <= highest; bits++) {
    code = (code + counts[bits - 1]) << 1;
    nextCode[bits] = code;
  }

  Tree* tree = newTree();

  for (int n = 0; n < size; n++) {
    int len = lengths[n];
    if (len != 0) {
      int code = nextCode[len];
      Tree* node = tree;
      nextCode[len]++;
      for (int i = 1; i <= len; i++) {
        if (code & (1 << (len - i))) {
          if (node->right == NULL) {
            node->right = newTree();
          }
          node = node->right;
        } else {
          if (node->left == NULL) {
            node->left = newTree();
          }
          node = node->left;
        }
      }
      node->value = n;
    }
  }

  return tree;
}

byte isComplete() {
  return complete;
}

int getBufferSize() {
  return BUFFER_SIZE;
}

byte* getOutputBuffer() {
  return output;
}

int readBits(int count) {
  // bytes go to bits like:
  //  byte num      0       1
  //           |00000000|00000000|
  //  bit num   76543210 FEDBCA98
  int value = currentBits;
  while (count > bitsLeft) {
    value |= (readInputByte() << bitsLeft);
    bitsLeft += 8;
  }

  int result = value;
  result &= ((1 << count) - 1);

  currentBits = value >> count;
  bitsLeft -= count;

  return result;
}

int readCode(Tree* tree) {
  if (tree == NULL) {
    error("Ended up on a null tree");
  }

  if (tree->value != -1) {
    return tree->value;
  }

  if (readBits(1)) {
    return readCode(tree->right);
  }

  return readCode(tree->left);
}

void initBlock() {
  if (complete) {
    error("Cannot read from completed stream");
  }

  if (blockLengthTree != NULL) {
    freeTree(blockLengthTree);
    blockLengthTree = NULL;
  }
  if (blockDistTree != NULL) {
    freeTree(blockDistTree);
    blockDistTree = NULL;
  }

  blockFinal = readBits(1);
  blockType = readBits(2);

  int i;

  // I'll be honest - only block type 2 has actually been tested

  if (blockType == 3) {
    error("Invalid block compression type");
  } else if (blockType == 0) { // uncompressed
    bitsLeft = 0;
    currentBits = 0;
    int len = (readInputByte() << 8) | readInputByte();
    int nlen = (readInputByte() << 8) | readInputByte();
    if (len != (-nlen + 1)) {
      error("Uncompressed block length encoding error");
    }
    blockLength = len;
  } else if (blockType == 2) { // Huffman coding - read in dynamic codes
    int hlit = readBits(5); // Number of literal codes - 257
    int hdist = readBits(5); // Number of distance codes - 1
    int hclen = readBits(4); // Number of code length codes - 4
    // Code Length codes come in a particular order:
    int codeLengths[] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    for (i = 0; i < hclen + 4; i++) {
      codeLengths[CL_ORDER[i]] = readBits(3);
    }
    Tree* codeTree = huffmanTreeFromLengths(19, codeLengths);

    int* lens = malloc((hlit + hdist + 258) * sizeof(int));
    i = 0;
    while (i < hlit + hdist + 258) {
      int code = readCode(codeTree);
      if (code <= 15) {
        lens[i++] = code;
      } else {
        int repeat = 0;
        int rcode = 0;
        if (code == 16) {
          repeat = readBits(2) + 3;
          rcode = lens[i - 1];
        } else if (code == 17) {
          repeat = readBits(3) + 3;
        } else if (code == 18) {
          repeat = readBits(7) + 11;
        }
        for (int j = 0; j < repeat; j++) {
          lens[i++] = rcode;
        }
      }
    }

    freeTree(codeTree);

    blockLengthTree = huffmanTreeFromLengths(hlit + 257, lens);
    blockDistTree = huffmanTreeFromLengths(hdist + 1, &lens[hlit + 257]);
    free(lens);
  } else { // Huffman coding - fixed codes
    int lengthLens[288];
    int distLens[32];
    int l = 0;
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

    for (int d = 0; d < 32; d++) {
      distLens[d] = 5;
    }

    blockLengthTree = huffmanTreeFromLengths(288, lengthLens);
    blockDistTree = huffmanTreeFromLengths(32, distLens);
  }
}

int codeToLength(int code) {
  if (code == 285) {
    return 258;
  }
  if (code < 265) {
    return code - 254;
  }

  int bits = (code - 261) >> 2;

  code -= 261 + (bits * 4);
  code <<= bits;
  code += (1 << (bits + 2)) + 3;
  code += readBits(bits);
  return code;
}

int codeToDistance(int code) {
  if (code < 4) {
    return code + 1;
  }

  int bits = max((code >> 1) - 1, 0);
  int base = code % 2;
  int lower = ((2 + base) << bits) + 1;
  return lower + readBits(bits);
}

void init() {
  output = malloc(BUFFER_SIZE);

  byte cmf = readInputByte();
  byte method = cmf & 0xF;
  // byte info = cmf >> 4;
  if (method != 8) {
    error("Unsupported compression method");
  }

  byte flags = readInputByte();
  // the fcheck value is just here to make sure that the (cmf * 256) + flags
  // value comes out as a multiple of 31. We don't actually need to use it.
  byte fcheck = flags & 0x1F;
  byte fdict = (flags & 0x20) == 0x20;
  // flevel not needed for decompression, ignore.
  // byte flevel = flags >> 6;

  if ((256 * cmf + flags) % 31 != 0) {
    error("Invalid flag check");
  }

  if (fdict) {
    error("Pre-defined dictionaries not yet supported");
  }

  initBlock();
}

int readValues() {
  if (blockType == 3) {
    error("Invalid block compression type");
  } else if (blockType == 0) { // uncompressed
    output[writePos++] = readInputByte();
    blockLength--;
  } else { // Huffman coding
    int value = readCode(blockLengthTree);
    if (value < 256) {
      output[writePos++] = (byte)value;
    } else if (value == 256) {
      if (blockFinal) {
        complete = true;
        // Could free these... but the module is actually now defunct, and
        // output at least might still be read from readValues(). May as well
        // just let the whole WASM instance be GC'd
        // freeTree(blockLengthTree);
        // freeTree(blockDistTree);
        // free(output);
        return writePos;
      }
      initBlock();
      return readValues();
    } else { // otherwise (length = 257..285)
      int length = codeToLength(value);
      int distance = codeToDistance(readCode(blockDistTree));
      int ptr = writePos - distance;
      while (ptr < 0) { // Don't just use % because JS uses signed mod
        ptr += BUFFER_SIZE;
      }
      for (int i = 0; i < length; i++) {
        output[writePos++ % BUFFER_SIZE] = output[ptr++ % BUFFER_SIZE];
      }
    }
  }
  writePos %= BUFFER_SIZE;
  return writePos;
}
