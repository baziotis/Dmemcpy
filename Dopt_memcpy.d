import core.simd: prefetch, void32, void16, storeUnaligned, loadUnaligned;

pragma(inline, true)
void mov16_u(void *dst, const void *src)
{
    storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
}

pragma(inline, true)
void mov32_u(void *dst, const void *src)
{
    storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
    storeUnaligned(cast(void16*)(dst+16), loadUnaligned(cast(const void16*)(src+16)));
}

pragma(inline, true)
void mov64_u(void *dst, const void *src)
{
    storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
    storeUnaligned(cast(void16*)(dst+16), loadUnaligned(cast(const void16*)(src+16)));
    storeUnaligned(cast(void16*)(dst+32), loadUnaligned(cast(const void16*)(src+32)));
    storeUnaligned(cast(void16*)(dst+48), loadUnaligned(cast(const void16*)(src+48)));
}

pragma(inline, true)
void mov128_a(void *dst, const void *src) {
    // Aligned AVX.
    *(cast(void32*)dst) = *(cast(const void32*)src);
    *(cast(void32*)(dst+32)) = *(cast(const void32*)(src+32));
    *(cast(void32*)(dst+64)) = *(cast(const void32*)(src+64));
    *(cast(void32*)(dst+96)) = *(cast(const void32*)(src+96));
    /*
       With steps of 256
    *(cast(void32*)(dst+128)) = *(cast(const void32*)(src+128));
    *(cast(void32*)(dst+160)) = *(cast(const void32*)(src+160));
    *(cast(void32*)(dst+192)) = *(cast(const void32*)(src+192));
    *(cast(void32*)(dst+224)) = *(cast(const void32*)(src+224));
    */


    /* With SSE
    storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
    storeUnaligned(cast(void16*)(dst+16), loadUnaligned(cast(const void16*)(src+16)));
    storeUnaligned(cast(void16*)(dst+32), loadUnaligned(cast(const void16*)(src+32)));
    storeUnaligned(cast(void16*)(dst+48), loadUnaligned(cast(const void16*)(src+48)));
    storeUnaligned(cast(void16*)(dst+64), loadUnaligned(cast(const void16*)(src+64)));
    storeUnaligned(cast(void16*)(dst+80), loadUnaligned(cast(const void16*)(src+80)));
    storeUnaligned(cast(void16*)(dst+96), loadUnaligned(cast(const void16*)(src+96)));
    storeUnaligned(cast(void16*)(dst+112), loadUnaligned(cast(const void16*)(src+112)));
    */
}

void mov128_u(void *dst, const void *src) {
    // Use AVX (there are no unaligned loads and stores for void32)
    asm pure nothrow @nogc {
        vmovdqu  YMM0, [RSI];
        vmovdqu  YMM1, [RSI+0x20];
        vmovdqu  YMM2, [RSI+0x40];
        vmovdqu  YMM3, [RSI+0x60];
        vmovdqu  [RDI], YMM0;
        vmovdqu  [RDI+0x20], YMM1;
        vmovdqu  [RDI+0x40], YMM2;
        vmovdqu  [RDI+0x60], YMM3;
    }
    /* Use SSE
    storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
    storeUnaligned(cast(void16*)(dst+16), loadUnaligned(cast(const void16*)(src+16)));
    storeUnaligned(cast(void16*)(dst+32), loadUnaligned(cast(const void16*)(src+32)));
    storeUnaligned(cast(void16*)(dst+48), loadUnaligned(cast(const void16*)(src+48)));
    storeUnaligned(cast(void16*)(dst+64), loadUnaligned(cast(const void16*)(src+64)));
    storeUnaligned(cast(void16*)(dst+80), loadUnaligned(cast(const void16*)(src+80)));
    storeUnaligned(cast(void16*)(dst+96), loadUnaligned(cast(const void16*)(src+96)));
    storeUnaligned(cast(void16*)(dst+112), loadUnaligned(cast(const void16*)(src+112)));
    */
}

// Could not be inlined
pragma(inline, false)
void mov128_up(void *dst, const void *src)
{
    enum WriteFetch = false;
    enum t0 = 3;
    prefetch!(WriteFetch, t0)(src+0x1a0);
    prefetch!(WriteFetch, t0)(src+0x260);
    mov128_u(dst, src);
}

/// IMPORTANT(stefanos)
/// IMPORTANT(stefanos)
//  I tried things in order, -- 1 --, -- 2 --, -- 3 --, -- 4 --.
// You can check in the comments what the changes were.

pragma(inline, false)
void Dopt(void *dst, const(void) *src, size_t n)
{
    // Align to 32-byte boundary. Move what is needed.
    int mod = cast(ulong)src & 0b11111;
    if (mod) {
        mov32_u(dst, src);
        src += 32 - mod;
        dst += 32 - mod;
        n -= 32 - mod;
    }

    // On some benchmarks, only moving
    // in 128 steps without prefetching was faster.

    if (n >= 20000) {
        for ( ; n >= 128; n -= 128) {
            mov128_up(dst, src);
            dst = dst + 128;
            src = src + 128;
        }
    } else {
        // -- 2 -- steps of 256
        for ( ; n >= 128; n -= 128) {
            mov128_a(dst, src);
            dst = dst + 128;
            src = src + 128;
        }
    }


    // Copy remaining < 128 bytes.
    if (n != 0) {
        // With inline ASM
        const(void) *a = src-128+n;
        void *b = dst-128+n;
        asm pure nothrow @nogc {
            mov     RSI, a;
            mov     RDI, b;
            vmovdqu  YMM0, [RSI];
            vmovdqu  YMM1, [RSI+0x20];
            vmovdqu  YMM2, [RSI+0x40];
            vmovdqu  YMM3, [RSI+0x60];
            vmovdqu  [RDI], YMM0;
            vmovdqu  [RDI+0x20], YMM1;
            vmovdqu  [RDI+0x40], YMM2;
            vmovdqu  [RDI+0x60], YMM3;
        }

        // Or with
        //mov128_u(dst - 128 + n, src - 128 + n);
    }


    /* Other alternative to move the remaining bytes.
    // 64-byte portions. 
    // <= 3 times loop.
    for (size_t i = n / 64; i; --i) {
        mov64_u(dst, src);
        n -= 64;
        dst = dst + 64;
        src = src + 64;
    }

    // 16-byte portions. 
    // <= 3 times loop.
    for (size_t i = n / 16; i; --i) {
        mov16_u(dst, src);
        n -= 16;
        dst = dst + 16;
        src = src + 16;
    }
    */
}
