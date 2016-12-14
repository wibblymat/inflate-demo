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
/* global WebAssembly, InflateJS, InflateWasm, InflateEmscripten */
/* eslint-disable guard-for-in */
'use strict';

let book;
let wasm;
let emWasm;
const stats = {};
const elements = {};
const output = document.getElementById('output');
const buttonsContainer = document.getElementById('buttons-container');
const nameRow = document.getElementById('name-row');
const lastRow = document.getElementById('last-row');
const firstRow = document.getElementById('first-row');
const averageRow = document.getElementById('average-row');
const countRow = document.getElementById('count-row');

const updateStats = function(tag, taken) {
  if (stats[tag].count === 0) {
    stats[tag].first = taken;
    elements[tag].first.textContent = `${taken}`;
  }
  stats[tag].total += taken;
  stats[tag].count++;

  elements[tag].last.textContent = `${taken}`;
  elements[tag].average.textContent = `${stats[tag].total / stats[tag].count}`;
  elements[tag].count.textContent = `${stats[tag].count}`;
};

const decompressJS = function() {
  const inflate = new InflateJS(book);
  return inflate.read();
};

const decompressEmscripten = function() {
  const inflate = new InflateEmscripten(emWasm, book);
  return inflate.read();
};

const decompressWASM = function() {
  const inflate = new InflateWasm(wasm, book);
  return inflate.read();
};

const versions = {
  js: {
    name: 'JS',
    func: decompressJS
  },
  wasm: {
    name: 'WASM (Binaryen)',
    func: decompressWASM
  },
  wasmEm: {
    name: 'WASM (Emscripten)',
    func: decompressEmscripten
  }
};

const load = function(url) {
  return fetch(url)
    .then(resp => resp.arrayBuffer())
    .then(buf => new Uint8Array(buf));
};

const run = function(tag) {
  const start = performance.now();
  let result = versions[tag].func();
  const taken = performance.now() - start;
  updateStats(tag, taken);
  output.textContent = result;
};

const run100 = function(tag) {
  for (let i = 0; i < 100; i++) {
    window.requestIdleCallback(() => run(tag));
  }
};

const init = function() {
  for (let tag in versions) {
    let runButton = document.createElement('button');
    runButton.textContent = `Decompress ${versions[tag].name}`;
    runButton.disabled = true;
    runButton.addEventListener('click', () => run(tag));

    let run100Button = document.createElement('button');
    run100Button.textContent = `Decompress ${versions[tag].name} x 100`;
    run100Button.disabled = true;
    run100Button.addEventListener('click', () => run100(tag));

    buttonsContainer.appendChild(runButton);
    buttonsContainer.appendChild(run100Button);

    let nameCell = document.createElement('th');
    nameCell.textContent = versions[tag].name;
    nameRow.appendChild(nameCell);
    let lastCell = document.createElement('td');
    lastRow.appendChild(lastCell);
    let firstCell = document.createElement('td');
    firstRow.appendChild(firstCell);
    let averageCell = document.createElement('td');
    averageRow.appendChild(averageCell);
    let countCell = document.createElement('td');
    countRow.appendChild(countCell);

    stats[tag] = {
      total: 0,
      count: 0,
      first: 0
    };

    elements[tag] = {
      run: runButton,
      run100: run100Button,
      last: lastCell,
      first: firstCell,
      average: averageCell,
      count: countCell
    };
  }
};

init();

const enableButtons = function() {
  for (let tag in versions) {
    elements[tag].run.disabled = false;
    elements[tag].run100.disabled = false;
  }
};

Promise.all([
  load('waroftheworlds.z'),
  load('wasm/inflate.wasm').then(buf => WebAssembly.compile(buf)),
  load('wasm/inflate-emscripten.wasm')
]).then(deps => {
  [book, wasm, emWasm] = deps;
  enableButtons();
});

