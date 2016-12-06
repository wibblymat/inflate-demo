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
const jsButton1000 = document.getElementById('js1000');
const jsLastOutput = document.getElementById('js-last');
const jsFirstOutput = document.getElementById('js-first');
const jsAverageOutput = document.getElementById('js-average');
const jsCountOutput = document.getElementById('js-count');
const wasmButton = document.getElementById('wasm');
const wasmButton1000 = document.getElementById('wasm1000');
const wasmLastOutput = document.getElementById('wasm-last');
const wasmFirstOutput = document.getElementById('wasm-first');
const wasmAverageOutput = document.getElementById('wasm-average');
const wasmCountOutput = document.getElementById('wasm-count');

const output = document.getElementById('output');
let input;

let jsTotal = 0;
let jsCount = 0;
let wasmTotal = 0;
let wasmCount = 0;

fetch('waroftheworlds.z')
  .then(resp => resp.arrayBuffer())
  .then(buf => new Uint8Array(buf))
  .then(arr => {
    jsButton.disabled = false;
    jsButton1000.disabled = false;
    wasmButton.disabled = false;
    wasmButton1000.disabled = false;
    input = arr;
  });

const decompressJS = function() {
  const start = performance.now();
  const inflate = new InflateJS(input);
  let result = inflate.read();
  const taken = performance.now() - start;
  if (jsCount === 0) {
    jsFirstOutput.textContent = `${taken}`;
  }
  jsTotal += taken;
  jsCount++;
  jsLastOutput.textContent = `${taken}`;
  jsAverageOutput.textContent = `${jsTotal / jsCount}`;
  jsCountOutput.textContent = `${jsCount}`;
  output.textContent = result;
};

const decompressWASM = function() {
  const start = performance.now();
  getWASMInflate(input).then(inflate => {
    let result = inflate.read();
    const taken = performance.now() - start;
    if (wasmCount === 0) {
      wasmFirstOutput.textContent = `${taken}`;
    }
    wasmTotal += taken;
    wasmCount++;
    wasmLastOutput.textContent = `${taken}`;
    wasmAverageOutput.textContent = `${wasmTotal / wasmCount}`;
    wasmCountOutput.textContent = `${wasmCount}`;
    output.textContent = result;
  });
};

const decompressJS1000 = function() {
  for (let i = 0; i < 1000; i++) {
    window.requestIdleCallback(decompressJS);
  }
};

const decompressWASM1000 = function() {
  for (let i = 0; i < 1000; i++) {
    window.requestIdleCallback(decompressWASM);
  }
};

jsButton.addEventListener('click', decompressJS);
jsButton1000.addEventListener('click', decompressJS1000);
wasmButton.addEventListener('click', decompressWASM);
wasmButton1000.addEventListener('click', decompressWASM1000);

