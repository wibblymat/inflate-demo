;;  Copyright 2016 Google Inc. All Rights Reserved.
;;  Licensed under the Apache License, Version 2.0 (the "License");
;;  you may not use this file except in compliance with the License.
;;  You may obtain a copy of the License at
;;      http://www.apache.org/licenses/LICENSE-2.0
;;  Unless required by applicable law or agreed to in writing, software
;;  distributed under the License is distributed on an "AS IS" BASIS,
;;  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;  See the License for the specific language governing permissions and
;;  limitations under the License.
(module
  (global $bitsLeft (mut i32) (i32.const 0))
  (global $currentBits (mut i32) (i32.const 0))
  (global $complete (mut i32) (i32.const 0))
  (global $writePos (mut i32) (i32.const 0))
  (global $inputPos (mut i32) (i32.const 0))
  (global $inputRemaining (mut i32) (i32.const 0))

  (global $blockType (mut i32) (i32.const 0))
  (global $blockFinal (mut i32) (i32.const 0))
  (global $blockLength (mut i32) (i32.const 0))
  (global $blockLengthTree (mut i32) (i32.const 0))
  (global $blockDistTree (mut i32) (i32.const 0))

  (global $OUTPUT_BUFFER (mut i32) (i32.const 0))
  (global $INPUT_BUFFER (mut i32) (i32.const 0))

  ;; Constants
  (global $BUFFER_SIZE i32 (i32.const 32768))

  ;; Pointers to memory locations
  (global $CL_ORDER i32 (i32.const 0))
  (global $ran_out_of_input_bytes i32 (i32.const 19))
  (global $ended_up_on_a_null_tree i32 (i32.const 44))
  (global $cannot_read_from_completed_stream i32 (i32.const 68))
  (global $invalid_block_compression_type i32 (i32.const 102))
  (global $uncompressed_block_length_encoding_error i32 (i32.const 133))
  (global $unsupported_compression_method i32 (i32.const 174))
  (global $invalid_flag_check i32 (i32.const 205))
  (global $pre_defined_dictionaries_not_yet_supported i32 (i32.const 224))

  (global $nextFree (mut i32) (i32.const 512))

  (import "env" "readInput" (func $readInput (param i32 i32) (result i32)))
  (import "env" "error" (func $error (param i32)))
  (import "env" "memset" (func $memset (param i32 i32 i32)))

  (memory (export "memory") 2)

  ;; 0 to 18 - code length order (bytes)
  (data (i32.const 0) "\10\11\12\00\08\07\09\06\0A\05\0B\04\0C\03\0D\02\0E\01\0F")
  (data (i32.const 19) "Ran out of input bytes\00")
  (data (i32.const 44) "Ended up on a null tree\00")
  (data (i32.const 68) "Cannot read from completed stream\00")
  (data (i32.const 102) "Invalid block compression type\00")
  (data (i32.const 133) "Uncompressed block length encoding error\00")
  (data (i32.const 174) "Unsupported compression method\00")
  (data (i32.const 205) "Invalid flag check\00")
  (data (i32.const 224) "Pre-defined dictionaries not yet supported\00")

  ;; This malloc is literally the worst
  (func $malloc (param $size i32) (result i32)
    (local $result i32)
    (set_local $result (get_global $nextFree))
    (set_global $nextFree (i32.add (get_global $nextFree) (get_local $size)))
    (return (get_local $result))
  )

  (func $free (param $ptr i32)
  )

  ;; Tree structure: (12 bytes)
  ;; tree+0 = value (i32)
  ;; tree+4 = left (i32)
  ;; tree+8 = right (i32)

  (func $newTree (result i32)
    (local $tree i32)
    (set_local $tree (call $malloc (i32.const 12)))
    (i32.store offset=0 (get_local $tree) (i32.const -1))
    (i32.store offset=4 (get_local $tree) (i32.const 0))
    (i32.store offset=8 (get_local $tree) (i32.const 0))
    (return (get_local $tree))
  )

  (func $freeTree (param $tree i32)
    (if (i32.ne (i32.load offset=4 (get_local $tree)) (i32.const 0))
      (call $freeTree (i32.load offset=4 (get_local $tree)))
    )
    (if (i32.ne (i32.load offset=8 (get_local $tree)) (i32.const 0))
      (call $freeTree (i32.load offset=8 (get_local $tree)))
    )
    (call $free (get_local $tree))
  )

  (func $max (param $a i32) (param $b i32) (result i32)
    (if (i32.gt_u (get_local $a) (get_local $b))
      (then (return (get_local $a)))
      (else (return (get_local $b)))
    )
  )

  (func $huffmanTreeFromLengths
    (param $size i32)
    (param $lengths i32)
    (result i32)

    (local $counts i32)
    (local $nextCode i32)
    (local $highest i32)
    (local $i i32)
    (local $bits i32)
    (local $n i32)
    (local $len i32)
    (local $lengths$i i32)
    (local $counts$lengths$i i32)
    (local $code i32)
    (local $node i32)
    (local $tree i32)

    ;; 288 * 4 = 1152 bytes. 288 is the maximum, some may be unused
    (set_local $counts (call $malloc (i32.const 1152)))
    ;; 16 * 4 = 64 bytes
    (set_local $nextCode (call $malloc (i32.const 64)))

    (call $memset (get_local $counts) (i32.const 0) (i32.const 1152))

    (set_local $i (i32.const 0))
    (block $end
      (loop $start
        (br_if $end
          (i32.ge_u (get_local $i) (get_local $size))
        )

        (set_local $lengths$i
          (i32.load
            (i32.add
              (get_local $lengths)
              (i32.mul
                (get_local $i)
                (i32.const 4)
              )
            )
          )
        )

        (set_local $highest
          (call $max
            (get_local $highest)
            (get_local $lengths$i)
          )
        )

        ;; Actually the *address* of counts[lengths[i]], not the value
        (set_local $counts$lengths$i
          (i32.add
            (get_local $counts)
            (i32.mul
              (get_local $lengths$i)
              (i32.const 4)
            )
          )
        )

        (i32.store
          (get_local $counts$lengths$i)
          (i32.add
            (i32.load (get_local $counts$lengths$i))
            (i32.const 1)
          )
        )

        (set_local $i (i32.add (get_local $i) (i32.const 1)))
        (br $start)
      )
    )

    (set_local $code (i32.const 0))
    ;; counts[0] = 0;
    (i32.store (get_local $counts) (i32.const 0))

    (set_local $bits (i32.const 1))
    (block $end
      (loop $start
        (br_if $end
          (i32.gt_u (get_local $bits) (get_local $highest))
        )

        ;; code = (code + counts[bits - 1]) << 1;
        (set_local $code
          (i32.shl
            (i32.add
              (get_local $code)
              (i32.load
                (i32.add
                  (get_local $counts)
                  (i32.mul
                    (i32.sub
                      (get_local $bits)
                      (i32.const 1)
                    )
                    (i32.const 4)
                  )
                )
               )
            )
            (i32.const 1)
          )
        )

        ;; nextCode[bits] = code;
        (i32.store
          (i32.add
            (get_local $nextCode)
            (i32.mul
              (get_local $bits)
              (i32.const 4)
            )
          )
          (get_local $code)
        )

        (set_local $bits (i32.add (get_local $bits) (i32.const 1)))

        (br $start)
      )
    )

    (set_local $tree (call $newTree))

    (set_local $n (i32.const 0))
    (block $end
      (loop $start
        (br_if $end (i32.ge_u (get_local $n) (get_local $size)))

        (set_local $len
          (i32.load
            (i32.add
              (get_local $lengths)
              (i32.mul
                (get_local $n)
                (i32.const 4)
              )
            )
          )
        )

        (if (i32.ne (get_local $len) (i32.const 0))
          (then
            (set_local $code
              (i32.load
                (i32.add
                  (get_local $nextCode)
                  (i32.mul
                    (get_local $len)
                    (i32.const 4)
                  )
                )
              )
            )
            (set_local $node (get_local $tree))
            (i32.store
              (i32.add
                (get_local $nextCode)
                (i32.mul
                  (get_local $len)
                  (i32.const 4)
                )
              )
              (i32.add
                (get_local $code)
                (i32.const 1)
              )
            )

            (set_local $i (i32.const 1))
            (block $end2
              (loop $start2
                (br_if $end2 (i32.gt_u (get_local $i) (get_local $len)))

                ;; if (code & (1 << (len - i))) {
                (if
                  (i32.and
                    (get_local $code)
                    (i32.shl
                      (i32.const 1)
                      (i32.sub
                        (get_local $len)
                        (get_local $i)
                      )
                    )
                  )
                  (then ;; right
                    (if (i32.eqz (i32.load offset=8 (get_local $node)))
                      (i32.store offset=8 (get_local $node) (call $newTree))
                    )
                    (set_local $node (i32.load offset=8 (get_local $node)))
                  )
                  (else ;; left
                    (if (i32.eqz (i32.load offset=4 (get_local $node)))
                      (i32.store offset=4 (get_local $node) (call $newTree))
                    )
                    (set_local $node (i32.load offset=4 (get_local $node)))
                  )
                )

                (set_local $i (i32.add (get_local $i) (i32.const 1)))
                (br $start2)
              )
            )

            (i32.store
              (get_local $node)
              (get_local $n)
            )
          )
        )

        (set_local $n (i32.add (get_local $n) (i32.const 1)))
        (br $start)
      )
    )

    (call $free (get_local $counts))
    (call $free (get_local $nextCode))

    (return (get_local $tree))
  )

  (func $isComplete (export "isComplete") (result i32)
    (get_global $complete)
  )

  (func $getBufferSize (export "getBufferSize") (result i32)
    (get_global $BUFFER_SIZE)
  )

  (func $getOutputBuffer (export "getOutputBuffer") (result i32)
    (get_global $OUTPUT_BUFFER)
  )

  (func $readInputByte (result i32)
    (local $result i32)
    (if (i32.eqz (get_global $inputRemaining))
      (block
        (set_global $inputRemaining
          (call $readInput
            (get_global $INPUT_BUFFER)
            (get_global $BUFFER_SIZE)
          )
        )
        (set_global $inputPos (i32.const 0))
      )
    )
    (if (i32.eqz (get_global $inputRemaining))
      (call $error (get_global $ran_out_of_input_bytes))
    )
    (set_global $inputRemaining
      (i32.sub
        (get_global $inputRemaining)
        (i32.const 1)
      )
    )
    (set_local $result
      (i32.load8_u
        (i32.add
          (get_global $INPUT_BUFFER)
          (get_global $inputPos)
        )
      )
    )
    (set_global $inputPos
      (i32.add
        (get_global $inputPos)
        (i32.const 1)
      )
    )
    (return (get_local $result))
  )

  (func $readBits (param $count i32) (result i32)
    (local $result i32)
    (local $value i32)
    ;; bytes go to bits like:
    ;; byte num      0       1
    ;;          |00000000|00000000|
    ;; bit num   76543210 FEDBCA98

    (set_local $value (get_global $currentBits))

    ;; while (count > bitsLeft) {
    ;;   value |= (readInputByte() << bitsLeft);
    ;;   bitsLeft += 8;
    ;; }
    (block $end
      (loop $start
        (br_if $end (i32.le_u (get_local $count) (get_global $bitsLeft)))
        (set_local $value
          (i32.or
            (get_local $value)
            (i32.shl
              (call $readInputByte)
              (get_global $bitsLeft)
            )
          )
        )
        (set_global $bitsLeft (i32.add (get_global $bitsLeft) (i32.const 8)))
        (br $start)
      )
    )

    (set_local $result
      (i32.and
        (get_local $value)
        (i32.sub
          (i32.shl
            (i32.const 1)
            (get_local $count)
          )
          (i32.const 1)
        )
      )
    )

    (set_global $currentBits
      (i32.shr_u
        (get_local $value)
        (get_local $count)
      )
    )

    (set_global $bitsLeft
      (i32.sub
        (get_global $bitsLeft)
        (get_local $count)
      )
    )

    (return (get_local $result))
  )

  (func $readCode (param $tree i32) (result i32)
    (local $value i32)

    (if (i32.eqz (get_local $tree))
      (call $error (get_global $ended_up_on_a_null_tree))
    )

    (set_local $value (i32.load offset=0 (get_local $tree)))

    (if (i32.ne (get_local $value) (i32.const -1))
      (return (get_local $value))
    )

    (if (call $readBits (i32.const 1))
      (return (call $readCode (i32.load offset=8 (get_local $tree))))
    )
    (return (call $readCode (i32.load offset=4 (get_local $tree))))
  )

  (func $initBlock
    (if (get_global $complete)
      (call $error (get_global $cannot_read_from_completed_stream))
    )

    (if (i32.ne (get_global $blockLengthTree) (i32.const 0))
      (block
        (call $freeTree (get_global $blockLengthTree))
        (set_global $blockLengthTree (i32.const 0))
      )
    )

    (if (i32.ne (get_global $blockDistTree) (i32.const 0))
      (block
        (call $freeTree (get_global $blockDistTree))
        (set_global $blockDistTree (i32.const 0))
      )
    )

    (set_global $blockFinal (call $readBits (i32.const 1)))
    (set_global $blockType (call $readBits (i32.const 2)))

    ;; I'll be honest - only block type 2 has actually been tested
    (if (i32.eq (get_global $blockType) (i32.const 0))
      ;; uncompressed
      (call $initUncompressed)
    )
    (if (i32.eq (get_global $blockType) (i32.const 1))
      ;; Huffman coding - fixed codes
      (call $initFixed)
    )
    (if (i32.eq (get_global $blockType) (i32.const 2))
      ;; Huffman coding - read in dynamic codes
      (call $initHuffman)
    )
    (if (i32.eq (get_global $blockType) (i32.const 3))
      (call $error (get_global $invalid_block_compression_type))
    )
  )

  (func $initUncompressed
    (unreachable)
;;     bitsLeft = 0;
;;     currentBits = 0;
;;     int len = (readInputByte() << 8) | readInputByte();
;;     int nlen = (readInputByte() << 8) | readInputByte();
;;     if (len != (-nlen + 1)) {
;;       error("Uncompressed block length encoding error");
;;     }
;;     blockLength = len;
  )

  (func $initHuffman
    (local $i i32)
    (local $j i32)
    (local $hlit i32)
    (local $hdist i32)
    (local $hclen i32)
    (local $codeLengths i32)
    (local $codeTree i32)
    (local $lens i32)
    (local $code i32)
    (local $repeat i32)
    (local $rcode i32)
    (local $total i32)

    ;; Number of literal codes - 257
    (set_local $hlit (call $readBits (i32.const 5)))

    ;; Number of distance codes - 1
    (set_local $hdist (call $readBits (i32.const 5)))

    ;; Number of code length codes - 4
    (set_local $hclen (call $readBits (i32.const 4)))

    ;; Code Length codes come in a particular order
    ;; 76 = 19 * 4
    (set_local $codeLengths (call $malloc (i32.const 76)))
    (call $memset (get_local $codeLengths) (i32.const 0) (i32.const 76))

    ;; for (i = 0; i < hclen + 4; i++) {
    (set_local $i (i32.const 0))
    (block $end
      (loop $start
        (br_if $end (i32.ge_u (get_local $i) (i32.add (get_local $hclen) (i32.const 4))))

        ;; codeLengths[CL_ORDER[i]] = readBits(3);
        (i32.store
          (i32.add
            (get_local $codeLengths)
            (i32.mul
              (i32.load8_u
                (i32.add
                  (get_global $CL_ORDER)
                  (get_local $i)
                )
              )
              (i32.const 4)
            )
          )
          (call $readBits (i32.const 3))
        )

        (set_local $i (i32.add (get_local $i) (i32.const 1)))

        (br $start)
      )
    )

    ;; Tree* codeTree = huffmanTreeFromLengths(19, codeLengths);
    (set_local $codeTree (call $huffmanTreeFromLengths (i32.const 19) (get_local $codeLengths)))

    (set_local $total
      (i32.add
        (i32.add
          (get_local $hlit)
          (get_local $hdist)
        )
        (i32.const 258)
      )
    )

    (set_local $lens
      (call $malloc
        (i32.mul
          (get_local $total)
          (i32.const 4)
        )
      )
    )

    (set_local $i (i32.const 0))
    (block $end
      (loop $start
        (br_if $end (i32.ge_u (get_local $i) (get_local $total)))

        (set_local $code (call $readCode (get_local $codeTree)))

        (if
          (i32.le_u (get_local $code) (i32.const 15))
          (then
            (i32.store
              (i32.add
                (get_local $lens)
                (i32.mul
                  (get_local $i)
                  (i32.const 4)
                )
              )
              (get_local $code)
            )
            (set_local $i (i32.add (get_local $i) (i32.const 1)))
          )
          (else
            (set_local $repeat (i32.const 0))
            (set_local $rcode (i32.const 0))

            (if (i32.eq (get_local $code) (i32.const 16))
              (block
                (set_local $repeat (i32.add (call $readBits (i32.const 2)) (i32.const 3)))
                (set_local $rcode
                  (i32.load
                    (i32.add
                      (get_local $lens)
                      (i32.mul
                        (i32.sub
                          (get_local $i)
                          (i32.const 1)
                        )
                        (i32.const 4)
                      )
                    )
                  )
                )
              )
            )
            (if (i32.eq (get_local $code) (i32.const 17))
              (then
                (set_local $repeat (i32.add (call $readBits (i32.const 3)) (i32.const 3)))
              )
            )
            (if (i32.eq (get_local $code) (i32.const 18))
              (then
                (set_local $repeat (i32.add (call $readBits (i32.const 7)) (i32.const 11)))
              )
            )

            (set_local $j (i32.const 0))
            (block $end2
              (loop $start2
                (br_if $end2 (i32.ge_u (get_local $j) (get_local $repeat)))

                (i32.store
                  (i32.add
                    (get_local $lens)
                    (i32.mul
                      (get_local $i)
                      (i32.const 4)
                    )
                  )
                  (get_local $rcode)
                )
                (set_local $i (i32.add (get_local $i) (i32.const 1)))
                (set_local $j (i32.add (get_local $j) (i32.const 1)))

                (br $start2)
              )
            )
          )
        )
        (br $start)
      )
    )

    (call $freeTree (get_local $codeTree))

    (set_global $blockLengthTree
      (call $huffmanTreeFromLengths
        (i32.add (get_local $hlit) (i32.const 257))
        (get_local $lens)
      )
    )

    (set_global $blockDistTree
      (call $huffmanTreeFromLengths
        (i32.add (get_local $hdist) (i32.const 1))
        (i32.add
          (get_local $lens)
          (i32.mul
            (i32.add
              (get_local $hlit)
              (i32.const 257)
            )
            (i32.const 4)
          )
        )
      )
    )

    (call $free (get_local $lens))
  )

  (func $initFixed
    (unreachable)
;;     int lengthLens[288];
;;     int distLens[32];
;;     int l = 0;
;;     while (l < 144) {
;;       lengthLens[l++] = 8;
;;     }
;;     while (l < 256) {
;;       lengthLens[l++] = 9;
;;     }
;;     while (l < 280) {
;;       lengthLens[l++] = 7;
;;     }
;;     while (l < 288) {
;;       lengthLens[l++] = 8;
;;     }
;;
;;     for (int d = 0; d < 32; d++) {
;;       distLens[d] = 5;
;;     }
;;
;;     blockLengthTree = huffmanTreeFromLengths(288, lengthLens);
;;     blockDistTree = huffmanTreeFromLengths(32, distLens);
  )

  (func $codeToLength (param $code i32) (result i32)
    (local $bits i32)
    (if (i32.eq (get_local $code) (i32.const 285))
      (return (i32.const 258))
    )
    (if (i32.lt_u (get_local $code) (i32.const 265))
      (return (i32.sub (get_local $code) (i32.const 254)))
    )

    ;; int bits = (code - 261) >> 2;
    (set_local $bits
      (i32.shr_u
        (i32.sub
          (get_local $code)
          (i32.const 261)
        )
        (i32.const 2)
      )
    )

    ;; code -= 261 + (bits * 4);
    ;; code <<= bits;
    ;; code += (1 << (bits + 2)) + 3;
    ;; code += readBits(bits);
    ;; return code;
    (return
      (i32.add
        (i32.add
          (i32.shl
            (i32.sub
              (get_local $code)
              (i32.add
                (i32.const 261)
                (i32.mul
                  (get_local $bits)
                  (i32.const 4)
                )
              )
            )
            (get_local $bits)
          )
          (i32.add
            (i32.shl
              (i32.const 1)
              (i32.add
                (get_local $bits)
                (i32.const 2)
              )
            )
            (i32.const 3)
          )
        )
        (call $readBits (get_local $bits))
      )
    )
  )

  (func $codeToDistance (param $code i32) (result i32)
    (local $bits i32)

    (if (i32.lt_u (get_local $code) (i32.const 4))
      (return (i32.add (get_local $code) (i32.const 1)))
    )

    ;; int bits = max((code >> 1) - 1, 0);
    (set_local $bits
      (call $max
        (i32.sub
          (i32.shr_u
            (get_local $code)
            (i32.const 1)
          )
          (i32.const 1)
        )
        (i32.const 0)
      )
    )

    ;; int base = code % 2;
    ;; int lower = ((2 + base) << bits) + 1;
    ;; return lower + readBits(bits);
    (return
      (i32.add
        (i32.add
          (i32.shl
            (i32.add
              (i32.const 2)
              (i32.rem_u
                (get_local $code)
                (i32.const 2)
              )
            )
            (get_local $bits)
          )
          (i32.const 1)
        )
        (call $readBits (get_local $bits))
      )
    )
  )

  (func $init (export "init")
    (local $cmf i32)
    (local $flags i32)

    (set_global $OUTPUT_BUFFER (call $malloc (get_global $BUFFER_SIZE)))
    (set_global $INPUT_BUFFER (call $malloc (get_global $BUFFER_SIZE)))

    (set_local $cmf (call $readInputByte))
    (if (i32.ne (i32.and (i32.const 0xf) (get_local $cmf)) (i32.const 8))
      (call $error (get_global $unsupported_compression_method))
    )

    (set_local $flags (call $readInputByte))


    ;; if ((256 * cmf + flags) % 31 != 0) {
    ;;   error("Invalid flag check");
    ;; }
    (if
      (i32.ne
        (i32.rem_u
          (i32.add
            (i32.mul
              (i32.const 256)
              (get_local $cmf)
            )
            (get_local $flags)
          )
          (i32.const 31)
        )
        (i32.const 0)
      )
      (call $error (get_global $invalid_flag_check))
    )

    ;; if ((flags & 0x20) == 0x20) {
    ;;   error("Pre-defined dictionaries not yet supported");
    ;; }
    (if (i32.eq (i32.and (get_local $flags) (i32.const 0x20)) (i32.const 0x20))
      (call $error (get_global $pre_defined_dictionaries_not_yet_supported))
    )

    (call $initBlock)
  )

  (func $readValues (export "readValues") (result i32)
    (local $value i32)
    (local $length i32)
    (local $distance i32)
    (local $ptr i32)
    (local $i i32)

    (if (i32.eq (get_global $blockType) (i32.const 3))
      (call $error (get_global $invalid_block_compression_type))
    )

    (if (i32.eqz (get_global $blockType))
      (then ;; uncompressed
        (i32.store8
          (i32.add
            (get_global $OUTPUT_BUFFER)
            (get_global $writePos)
          )
          (call $readInputByte)
        )
        (set_global $writePos
          (i32.add (get_global $writePos) (i32.const 1))
        )
        (set_global $blockLength
          (i32.sub (get_global $blockLength) (i32.const 1))
        )
      )
      (else ;; Huffman coding
        (set_local $value (call $readCode (get_global $blockLengthTree)))
        (if (i32.lt_u (get_local $value) (i32.const 256))
          (then ;; value < 256
            (i32.store8
              (i32.add
                (get_global $OUTPUT_BUFFER)
                (get_global $writePos)
              )
              (get_local $value)
            )
            (set_global $writePos
              (i32.add (get_global $writePos) (i32.const 1))
            )
          )
          (else
            (if (i32.eq (get_local $value) (i32.const 256))
              (then ;; value == 256
                (if (get_global $blockFinal)
                  (block
                    (set_global $complete (i32.const 1))
                    (return (get_global $writePos))
                  )
                )

                (call $initBlock)
                (return (call $readValues))
              )
              (else ;; otherwise (length = 257..285)
                (set_local $length (call $codeToLength (get_local $value)))
                (set_local $distance
                  (call $codeToDistance
                    (call $readCode (get_global $blockDistTree))
                  )
                )

                (set_local $ptr
                  (i32.rem_u
                    (i32.sub (get_global $writePos) (get_local $distance))
                    (get_global $BUFFER_SIZE)
                  )
                )

                (set_local $i (i32.const 0))
                (block $end
                  (loop $start
                    (br_if $end (i32.ge_u (get_local $i) (get_local $length)))

                    ;; output[writePos % BUFFER_SIZE] = output[ptr % BUFFER_SIZE];
                    (i32.store8
                      (i32.add
                        (get_global $OUTPUT_BUFFER)
                        (i32.rem_u
                          (get_global $writePos)
                          (get_global $BUFFER_SIZE)
                        )
                      )
                      (i32.load8_u
                        (i32.add
                          (get_global $OUTPUT_BUFFER)
                          (i32.rem_u
                            (get_local $ptr)
                            (get_global $BUFFER_SIZE)
                          )
                        )
                      )
                    )

                    (set_local $i (i32.add (get_local $i) (i32.const 1)))
                    (set_local $ptr (i32.add (get_local $ptr) (i32.const 1)))
                    (set_global $writePos (i32.add (get_global $writePos) (i32.const 1)))
                    (br $start)
                  )
                )

              )
            )
          )
        )
      )
    )
    (set_global $writePos (i32.rem_u (get_global $writePos) (get_global $BUFFER_SIZE)))
    (return (get_global $writePos))
  )
)
