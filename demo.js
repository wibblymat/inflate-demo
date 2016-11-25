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
/* global InflateJS, getWASMInflate */
'use strict';

const jsButton = document.getElementById('js');
const jsTimerOutput = document.getElementById('js-timer');
const wasmButton = document.getElementById('wasm');
const wasmTimerOutput = document.getElementById('wasm-timer');

const output = document.getElementById('output');
let input;

fetch('waroftheworlds.z')
  .then(resp => resp.arrayBuffer())
  .then(buf => new Uint8Array(buf))
  .then(arr => {
    jsButton.disabled = false;
    wasmButton.disabled = false;
    input = arr;
  });

const decompressJS = function() {
  const start = performance.now();
  const inflate = new InflateJS(input);
  let result = inflate.read();
  jsTimerOutput.textContent = `${performance.now() - start} ms`;
  output.textContent = result;
};

const decompressWASM = function() {
  const start = performance.now();
  getWASMInflate(input).then(inflate => {
    let result = inflate.read();
    wasmTimerOutput.textContent = `${performance.now() - start} ms`;
    output.textContent = result;
  });
};

jsButton.addEventListener('click', decompressJS);
wasmButton.addEventListener('click', decompressWASM);

