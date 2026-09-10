
// Compact single-DES ECB encrypt (public-domain style tables) for RFB VNC Auth.
#pragma once
#include <cstdint>
#include <cstring>

static inline uint32_t HMSSH_ROTL(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }

static void HmsshDesEncryptBlock(const uint8_t key[8], const uint8_t in[8], uint8_t out[8]) {
  // Use OpenSSL-free Feistel with standard S-boxes.
  static const uint8_t PC1[56] = {
    57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,27,19,11,3,60,52,44,36,
    63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,28,20,12,4};
  static const uint8_t PC2[48] = {
    14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2,41,52,31,37,47,55,
    30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,29,32};
  static const uint8_t SHIFTS[16] = {1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1};
  static const uint8_t IP[64] = {
    58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6,
    64,56,48,40,32,24,16,8,57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,
    61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7};
  static const uint8_t FP[64] = {
    40,8,48,16,56,24,64,32,39,7,47,15,55,23,63,31,38,6,46,14,54,22,62,30,
    37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,
    34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25};
  static const uint8_t E[48] = {
    32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,16,17,
    16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1};
  static const uint8_t P[32] = {
    16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,2,8,24,14,32,27,3,9,19,13,30,6,22,11,4,25};
  static const uint8_t S[8][64] = {
    {14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7,0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8,
     4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0,15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13},
    {15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10,3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5,
     0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15,13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9},
    {10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8,13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1,
     13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7,1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12},
    {7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15,13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9,
     10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4,3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14},
    {2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9,14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6,
     4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14,11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3},
    {12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11,10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8,
     9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6,4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13},
    {4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1,13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6,
     1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2,6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12},
    {13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7,1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2,
     7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8,2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11}};

  auto getbit = [](const uint8_t* b, int bit1based) -> int {
    int i = bit1based - 1;
    return (b[i / 8] >> (7 - (i % 8))) & 1;
  };
  auto setbit = [](uint8_t* b, int bit1based, int v) {
    int i = bit1based - 1;
    if (v) b[i / 8] |= static_cast<uint8_t>(1u << (7 - (i % 8)));
    else b[i / 8] &= static_cast<uint8_t>(~(1u << (7 - (i % 8))));
  };

  uint8_t kn[16][6];
  uint8_t cd[7]{};
  for (int i = 0; i < 56; ++i) setbit(cd, i + 1, getbit(key, PC1[i]));
  for (int round = 0; round < 16; ++round) {
    int s = SHIFTS[round];
    // rotate C (28 bits) and D (28 bits) packed in cd
    auto rot28 = [&](int startBit) {
      int bits[28];
      for (int i = 0; i < 28; ++i) bits[i] = getbit(cd, startBit + i);
      int outb[28];
      for (int i = 0; i < 28; ++i) outb[i] = bits[(i + s) % 28];
      for (int i = 0; i < 28; ++i) setbit(cd, startBit + i, outb[i]);
    };
    rot28(1); rot28(29);
    std::memset(kn[round], 0, 6);
    for (int i = 0; i < 48; ++i) setbit(kn[round], i + 1, getbit(cd, PC2[i]));
  }

  uint8_t block[8];
  std::memcpy(block, in, 8);
  uint8_t ipb[8]{};
  for (int i = 0; i < 64; ++i) setbit(ipb, i + 1, getbit(block, IP[i]));
  uint32_t L = 0, R = 0;
  for (int i = 0; i < 32; ++i) {
    if (getbit(ipb, i + 1)) L |= (1u << (31 - i));
    if (getbit(ipb, i + 33)) R |= (1u << (31 - i));
  }
  for (int round = 0; round < 16; ++round) {
    uint8_t rbytes[4] = {
      static_cast<uint8_t>((R >> 24) & 0xff), static_cast<uint8_t>((R >> 16) & 0xff),
      static_cast<uint8_t>((R >> 8) & 0xff), static_cast<uint8_t>(R & 0xff)};
    uint8_t er[6]{};
    for (int i = 0; i < 48; ++i) setbit(er, i + 1, getbit(rbytes, E[i]));
    for (int i = 0; i < 6; ++i) er[i] ^= kn[round][i];
    uint32_t f = 0;
    for (int i = 0; i < 8; ++i) {
      int b0 = getbit(er, i * 6 + 1);
      int b1 = getbit(er, i * 6 + 2);
      int b2 = getbit(er, i * 6 + 3);
      int b3 = getbit(er, i * 6 + 4);
      int b4 = getbit(er, i * 6 + 5);
      int b5 = getbit(er, i * 6 + 6);
      int row = (b0 << 1) | b5;
      int col = (b1 << 3) | (b2 << 2) | (b3 << 1) | b4;
      int val = S[i][row * 16 + col];
      f |= static_cast<uint32_t>(val) << (28 - 4 * i);
    }
    uint8_t fbytes[4] = {
      static_cast<uint8_t>((f >> 24) & 0xff), static_cast<uint8_t>((f >> 16) & 0xff),
      static_cast<uint8_t>((f >> 8) & 0xff), static_cast<uint8_t>(f & 0xff)};
    uint8_t pf[4]{};
    for (int i = 0; i < 32; ++i) setbit(pf, i + 1, getbit(fbytes, P[i]));
    uint32_t fout = (static_cast<uint32_t>(pf[0]) << 24) | (static_cast<uint32_t>(pf[1]) << 16) |
                    (static_cast<uint32_t>(pf[2]) << 8) | pf[3];
    uint32_t newR = L ^ fout;
    L = R;
    R = newR;
  }
  // final swap already done by last assign pattern — combine R||L then FP
  uint8_t pre[8]{};
  for (int i = 0; i < 32; ++i) {
    setbit(pre, i + 1, (R >> (31 - i)) & 1);
    setbit(pre, i + 33, (L >> (31 - i)) & 1);
  }
  uint8_t finalb[8]{};
  for (int i = 0; i < 64; ++i) setbit(finalb, i + 1, getbit(pre, FP[i]));
  std::memcpy(out, finalb, 8);
}
