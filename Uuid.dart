#library('Uuid');
#import('dart:crypto');

/**
 *  uuid for Dart
 *
 *  Copyright (c) 2012 Yulian Kuncheff
 *
 *  Released under MIT License.
 *
 *  Based on node-uuid by Robert Kieffer.
 */

class Uuid {
  static final TAU = 2*Math.PI;
  var _rndBytes, _seedBytes, _nodeId, _clockSeq, _lastMSecs = 0,
      _lastNSecs = 0;
  var _byteToHex, _hexToByte;

  Uuid() {
    _rndBytes = new List(16);
    _byteToHex = new List(256);
    _hexToByte = new Map();

    // Easy number <-> hex conversion
    for(var i = 0; i < 256; i++) {
      var hex = new List<int>();
      hex.add(i);
      _byteToHex[i] = CryptoUtils.bytesToHex(hex);
      _hexToByte[_byteToHex[i]] = i;
    }

    // Sets initial seedBytes, node, and clock seq based on MathRNG.
    _seedBytes = mathRNG();

    // Per 4.5, create a 48-bit node id (47 random bits + multicast bit = 1)
    _nodeId = [_seedBytes[0] | 0x01,
               _seedBytes[1], _seedBytes[2], _seedBytes[3],
               _seedBytes[4], _seedBytes[5]];

    // Per 4.2.2, randomize (14 bit) clockseq
    _clockSeq = (_seedBytes[6] << 8 | _seedBytes[7]) & 0x3ffff;
  }

  /**
   * Math.Random()-based RNG. All platforms, fast, not cryptographically strong.
   */
  List mathRNG() {
    var rand, b = _rndBytes;

    for(var i = 0; i < 16; i++) {
      if ((i & 0x03) == 0) {
        rand = (Math.random() * 0x100000000).floor().toInt();
      }
      b[i] = rand >> ((i & 0x03) << 3) & 0xff;
    }

    return b;
  }

  /**
   * Parses the provided [uuid] into a list of byte values.
   * Can optionally be provided a [buffer] to write into and
   *  a positional [offset] for where to start inputting into the buffer.
   */
  List parse(String uuid, [List buffer, int offset=0]) {
    var i = offset, ii = 0;

    // Create a 16 item buffer if one hasn't been provided.
    buffer = (buffer != null) ? buffer : new List(16);

    // Convert to lowercase and split into 2 character string list.
    // It would be better to use String.split() but the RegEx of
    // '[0-9a-z]{2}' did not split it at all, so I split it manually.
    uuid = uuid.toLowerCase().replaceAll('-','');
    var charSplit = uuid.splitChars();
    var c2Split = new List();
    for(var j = 0; j < charSplit.length; j+=2) {
      c2Split.add('${charSplit[j]}${charSplit[j+1]}');
    }

    // Got through the hex list and turn it into a byte buffer.
    for(var oct in c2Split) {
      if (ii < 16) {
        buffer[i + ii++] = _hexToByte[oct];
      }
    };

    // Zero out any left over bytes if the string was too short.
    while (ii < 16) {
      buffer[i + ii++] = 0;
    }

    return buffer;
  }

  /**
   * Unparses a [buffer] of bytes and outputs a proper UUID string.
   * An optional [offset] is allowed if you want to start at a different point
   *  in the buffer.
   */
  String unparse(List buffer, [int offset=0]) {
    var i = offset;
    return '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}'
           '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}-'
           '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}-'
           '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}-'
           '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}-'
           '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}'
           '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}'
           '${_byteToHex[buffer[i++]]}${_byteToHex[buffer[i++]]}';
  }

  /**
   * v1() Generates a time-based version 1 UUID
   *
   * By default it will generate a string based off current time, and will
   * return a string.
   *
   * If an optional [buffer] list is provided, it will put the byte data into
   * that buffer and return a buffer.
   *
   * Optionally an [offset] can be provided with a start position in the buffer.
   *
   * The first argument is an options map that takes various configuration
   * options detailed in the readme.
   *
   * http://tools.ietf.org/html/rfc4122.html#section-4.2.2
   */
  v1([Map options = null, List buffer, int offset=0]) {
    var i = offset;
    var buf = (buffer != null) ? buffer : new List(16);
    options = (options != null) ? options : new Map();

    var clockSeq = (options['clockSeq'] != null) ? options['clockSeq'] : _clockSeq;

    // UUID timestamps are 100 nano-second units since the Gregorian epoch,
    // (1582-10-15 00:00). Time is handled internally as 'msecs' (integer
    // milliseconds) and 'nsecs' (100-nanoseconds offset from msecs) since unix
    // epoch, 1970-01-01 00:00.
    var mSecs = (options['mSecs'] != null) ? options['mSecs'] : (new Date.now()).millisecondsSinceEpoch;

    // Per 4.2.1.2, use count of uuid's generated during the current clock
    // cycle to simulate higher resolution clock
    var nSecs = (options['nSecs'] != null) ? options['nSecs'] : _lastNSecs + 1;

    // Time since last uuid creation (in msecs)
    var dt = (mSecs - _lastMSecs) + (nSecs - _lastNSecs)/10000;

    // Per 4.2.1.2, Bump clockseq on clock regression
    if (dt < 0 && options['clockSeq'] == null) {
      clockSeq = clockSeq + 1 & 0x3fff;
    }

    // Reset nsecs if clock regresses (new clockseq) or we've moved onto a new
    // time interval
    if ((dt < 0 || mSecs > _lastMSecs) && options['nSecs'] == null) {
      nSecs = 0;
    }

    // Per 4.2.1.2 Throw error if too many uuids are requested
    if (nSecs >= 10000) {
      throw new Exception('uuid.v1(): Can\'t create more than 10M uuids/sec');
    }

    _lastMSecs = mSecs;
    _lastNSecs = nSecs;
    _clockSeq = clockSeq;

    // Per 4.1.4 - Convert from unix epoch to Gregorian epoch
    mSecs += 12219292800000;

    // time Low
    var tl = ((mSecs & 0xfffffff) * 10000 + nSecs) % 0x100000000;
    buf[i++] = tl >> 24 & 0xff;
    buf[i++] = tl >> 16 & 0xff;
    buf[i++] = tl >> 8 & 0xff;
    buf[i++] = tl & 0xff;

    // time mid
    var tmh = (mSecs / 0x100000000 * 10000).toInt() & 0xfffffff;
    buf[i++] = tmh >> 8 & 0xff;
    buf[i++] = tmh & 0xff;

    // time high and version
    buf[i++] = tmh >> 24 & 0xf | 0x10; // include version
    buf[i++] = tmh >> 16 & 0xff;

    // clockSeq high and reserved (Per 4.2.2 - include variant)
    buf[i++] = clockSeq >> 8 | 0x80;

    // clockSeq low
    buf[i++] = clockSeq & 0xff;

    // node
    var node = (options['node'] != null) ? options['node'] : _nodeId;
    for (var n = 0; n < 6; n++) {
      buf[i + n] = node[n];
    }

    return (buffer != null) ? buffer : unparse(buf);
  }

  /**
   * v4() Generates a time-based version 4 UUID
   *
   * By default it will generate a string based Math.random(), and will return
   * a string.
   *
   * If an optional [buffer] list is provided, it will put the byte data into
   * that buffer and return a buffer.
   *
   * Optionally an [offset] can be provided with a start position in the buffer.
   *
   * The first argument is an options map that takes various configuration
   * options detailed in the readme.
   *
   * http://tools.ietf.org/html/rfc4122.html#section-4.4
   */
  v4([Map options = null, List buffer, int offset=0]) {
    var i = offset;
    options = (options != null) ? options : new Map();

    // Use the built-in RNG or a custom provided RNG
    var rng = (options['rng'] != null) ? options['rng'] : mathRNG();

    // Use provided values over RNG
    var rnds = (options['random'] != null) ? options['random'] : rng;

    // per 4.4, set bits for version and clockSeq high and reserved
    rnds[6] = (rnds[6] & 0x0f) | 0x40;
    rnds[8] = (rnds[6] & 0x3f) | 0x80;

    // Copy the bytes to the buffer if one is provided.
    if (buffer != null) {
      for (var j = 0; j < 16; j++) {
        buffer[i+j] = rnds[j];
      }
    }

    return (buffer != null) ? buffer : unparse(rnds);
  }


}