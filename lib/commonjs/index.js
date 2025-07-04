"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
var _audioPro = require("./audioPro.js");
Object.keys(_audioPro).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _audioPro[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _audioPro[key];
    }
  });
});
var _useAudioPro = require("./useAudioPro.js");
Object.keys(_useAudioPro).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _useAudioPro[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _useAudioPro[key];
    }
  });
});
var _types = require("./types.js");
Object.keys(_types).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _types[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _types[key];
    }
  });
});
var _values = require("./values.js");
Object.keys(_values).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _values[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _values[key];
    }
  });
});
//# sourceMappingURL=index.js.map