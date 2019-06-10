import std.datetime.stopwatch;
import core.stdc.string;
import S_struct;
import std.random;
import std.traits;
import std.stdio;


bool isPowerOf2(T)(T x)
    if (isIntegral!T)
{
    return (x != 0) && ((x & (x - 1)) == 0);
}

void Cmemcpy(T)(T *dst, const T *src)
{
    pragma(inline, true)
    memcpy(dst, src, T.sizeof);
}

void Dmemcpy(T)(T *dst, const T *src)
    if (isScalarType!T)
{
    pragma(inline, true)
    *dst = *src;
}

// This implementation handles type sizes that are not powers of 2
// This implementation can't be @safe because it does pointer arithmetic
void DmemcpyUnsafe(T)(T *dst, const T *src) @trusted
   if (is(T == struct))
{
    import core.bitop: bsr;
    
    static assert(T.sizeof != 0);
    enum prevPowerOf2 = 1LU << bsr(T.sizeof);
    alias TRemainder = S!(T.sizeof - prevPowerOf2);
    auto s = cast(const S!prevPowerOf2*)(src);
    auto d = cast(S!prevPowerOf2*)(dst);
    static if (T.sizeof < 31) {
        pragma(inline, true);
        Dmemcpy(d, s);
        Dmemcpy(cast(TRemainder*)(d + 1), cast(const TRemainder*)(s + 1));
    } else {
        Dmemcpy(d, s);
        Dmemcpy(cast(TRemainder*)(d + 1), cast(const TRemainder*)(s + 1));
    }
}


pragma(inline, true)
void Dmemcpy(T)(T *dst, const T *src)
    if (is(T == struct))
{
    static if (T.sizeof == 1)
    {
        pragma(inline, true)
        Dmemcpy(cast(ubyte*)(dst), cast(const ubyte*)(src));
        return;
    }
    else static if (T.sizeof == 2)
    {
        pragma(inline, true)
        Dmemcpy(cast(ushort*)(dst), cast(const ushort*)(src));
        return;
    }
    else static if (T.sizeof == 4)
    {
        pragma(inline, true)
        Dmemcpy(cast(uint*)(dst), cast(const uint*)(src));
        return;
    }
    else static if (T.sizeof == 8)
    {
        pragma(inline, true)
        Dmemcpy(cast(ulong*)(dst), cast(const ulong*)(src));
        return;
    }
    else static if (T.sizeof == 16)
    {
        version(D_SIMD)
        {
            pragma(inline, true)
            pragma(msg, "SIMD ", T);
            import core.simd: void16, storeUnaligned, loadUnaligned;
            storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
        }
        else
        {
            //pragma(inline, true)
            static foreach(i; 0 .. T.sizeof/8)
            {
                Dmemcpy((cast(ulong*)dst) + i, (cast(const long*)src) + i);
            }
        }

        return;
    }
    else static if (T.sizeof == 32)
    {
        //pragma(inline, true)
        static foreach(i; 0 .. T.sizeof/16)
        {
            Dmemcpy((cast(S!16*)dst) + i, (cast(const S!16*)src) + i);
        }
        return;
    }
    else static if (T.sizeof < 64 && !isPowerOf2(T.sizeof))
    {
        pragma(inline, true)
        DmemcpyUnsafe(dst, src);
        return;
    }
    else static if (T.sizeof == 64) {
        Dmemcpy(cast(S!32*)dst, cast(const S!32*)src) ;
        Dmemcpy((cast(S!32*)dst) + 1, (cast(const S!32*)src) + 1);
    }



///
/// NOTE - IMPORTANT(stefanos): Any assembly code here is (possibly a lot)
/// slower than if you took it, compiled it with an assembler and linked
/// the object file. See NOTES - TODO.txt for more info.
///





    
    else static if (T.sizeof < 256) {
        pragma(inline, false)
        // GCC version
        // Optimized to reach alignment.
        // NOTE(stefanos): I reached more speed with the previous
        // version, making it use AVX instructions.
        asm pure nothrow @nogc {
            //mov     RSI, src;
            //mov     RDI, dst;
            mov     RDX, T.sizeof;
            mov RCX, RSI;
            and RCX, 15;
            je  L1000;
            // if (mod) 
            movdqu  XMM0,  [RSI];
            movdqu  [RDI], XMM0;
            mov     RAX, 16;
            sub     RAX, RCX;
            // s += 16 - mod1
            add RSI, RAX;
            // d += 16 - mod1
            add RDI, RAX;
            // n -= 16 - mod1
            sub RDX, RAX;

        L1000:
            mov    RAX,RDI;
            mov    RDI,RDX;
            mov    RCX,0x3;
            shr    RDI,0x6;
            sub    RCX,RDI;
            cmp    RCX,0x1;
            je     L1;
            jb     L4;
            cmp    RCX,0x2;
            je     L2;
            mov    RCX,RAX;
        L8:
            mov    RDI,RDX;
            mov    R8D,0x3;
            shr    RDI,0x4;
            sub    R8,RDI;
            cmp    R8,0x1;
            je     L3;
            jb     L5;
            cmp    R8,0x2;
            jne    L6;
        L9:
            movdqu XMM0, [RSI];
            movdqu  [RCX],XMM0;
            sub    RDX,0x10;
            add    RCX,0x10;
            add    RSI,0x10;
        L6:
            test   RDX,RDX;
            je     L7;
            sub    RDX,0x10;
            add    RSI,RDX;
            add    RCX,RDX;
            movdqu XMM0, [RSI];
            movdqu  [RCX],XMM0;
        L7:
            nop    ;
        }
        return;
        asm pure nothrow @nogc {
        L2:
            mov    RCX,RAX;
        L10:
            movdqu XMM0, [RSI];
            movdqu XMM1, [RSI+0x10];
            movdqu XMM2, [RSI+0x20];
            movdqu XMM3, [RSI+0x30];
            movdqu  [RCX],XMM0;
            movdqu  [RCX+0x10],XMM1;
            movdqu  [RCX+0x20],XMM2;
            movdqu  [RCX+0x30],XMM3;
            sub    RDX,0x40;
            add    RCX,0x40;
            add    RSI,0x40;
            jmp    L8;
            nop    ;
        L5:
            movdqu XMM0, [RSI];
            movdqu  [RCX],XMM0;
            sub    RDX,0x10;
            add    RCX,0x10;
            add    RSI,0x10;
        L3:
            movdqu XMM0, [RSI];
            movdqu  [RCX],XMM0;
            sub    RDX,0x10;
            add    RCX,0x10;
            add    RSI,0x10;
            jmp    L9;
            nop    ;
        L4:
            movdqu XMM0, [RSI];
            movdqu XMM1, [RSI+0x10];
            movdqu XMM2, [RSI+0x20];
            movdqu XMM3, [RSI+0x30];
            movdqu  [RAX],XMM0;
            movdqu  [RAX+0x10],XMM1;
            movdqu  [RAX+0x20],XMM2;
            movdqu  [RAX+0x30],XMM3;
            sub    RDX,0x40;
            lea    RCX,[RAX+0x40];
            add    RSI,0x40;
        L11:
            movdqu XMM0, [RSI];
            movdqu XMM1, [RSI+0x10];
            movdqu XMM2, [RSI+0x20];
            movdqu XMM3, [RSI+0x30];
            movdqu  [RCX],XMM0;
            movdqu  [RCX+0x10],XMM1;
            movdqu  [RCX+0x20],XMM2;
            movdqu  [RCX+0x30],XMM3;
            sub    RDX,0x40;
            add    RCX,0x40;
            add    RSI,0x40;
            jmp    L10;
            nop    ;
        L1:
            mov    RCX,RAX;
            jmp    L11;
        }
    }
    else
    {
        pragma(inline, false)
        asm pure nothrow @nogc {
            mov    RDX, T.sizeof;
            cmp    RDX, 0x7f;
            jbe    L5;     // if (n < 128)
            mov    ECX, ESI;                       // save `src`
            and    ECX, 0x1f;                      // mod = src % 32
            je     L1;
            // if (mod) -> copy enough bytes to reach 32-byte alignment
            movdqu XMM0, [RSI];
            movdqu XMM1, [RSI+0x10];
            movdqu [RDI], XMM0;
            movdqu [RDI+0x10], XMM1;
            // %t0 = 32 - mod
            mov    RAX, 0x20;
            sub    RAX, RCX;
            //cdqe   ;
            // src += %t0
            add    RSI, RAX;
            // dst += %t0
            add    RDI, RAX;
            // n -= %t0
            sub    RDX, RAX;
        L1:
            cmp    RDX, 0x7f;
            jbe    L2;
        // if (n >= 128)
        align 16;
        L4:
            // Because of the above, (at least) the loads
            // are 32-byte aligned.
            vmovdqu YMM0, [RSI];
            vmovdqu YMM1, [RSI+0x20];
            vmovdqu YMM2, [RSI+0x40];
            vmovdqu YMM3, [RSI+0x60];
            vmovdqu [RDI], YMM0;
            vmovdqu [RDI+0x20], YMM1;
            vmovdqu [RDI+0x40], YMM2;
            vmovdqu [RDI+0x60], YMM3;
            // src += 128;
            add    RSI, 128;
            // dst += 128;
            add    RDI, 128;
            // n -= 128;
            sub    RDX, 128;
            // if (n >= 128) loop
            cmp    RDX, 128;
            jge    L4;
        L2:
            test   RDX, RDX;
            je     L3;
            // if (n != 0)  -> copy the remaining <= 128 bytes
            lea    RSI, [RSI-128+RDX];
            lea    RDI, [RDI-128+RDX];
            vmovdqu YMM0, [RSI];
            vmovdqu YMM1, [RSI+0x20];
            vmovdqu YMM2, [RSI+0x40];
            vmovdqu YMM3, [RSI+0x60];
            vmovdqu [RDI], YMM0;
            vmovdqu [RDI+0x20], YMM1;
            vmovdqu [RDI+0x40], YMM2;
            vmovdqu [RDI+0x60], YMM3;
        L3:
            vzeroupper;
        }
        return;
        asm pure nothrow @nogc {
        L5:
            // if (n < 128)
            vmovdqu YMM0, [RSI];
            vmovdqu YMM1, [RSI+0x20];
            vmovdqu [RDI], YMM0;
            vmovdqu [RDI+0x20], YMM1;
            sub     RDX, 0x40;
            add     RSI, RDX;
            add     RDI, RDX;
            vmovdqu YMM0, [RSI];
            vmovdqu YMM1, [RSI+0x20];
            vmovdqu [RDI], YMM0;
            vmovdqu [RDI+0x20], YMM1;
        }
        return;
    }
}
